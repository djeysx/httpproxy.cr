require "http"

class HttpProxy::ProxyHandler
  include HTTP::Handler

  def call(context)
    case context.request.method
    when "CONNECT"
      handle_tunneling(context)
    else
      handle_http(context)
    end
  end

  private def handle_tunneling(context)
    host, port = context.request.resource.split(":", 2)
    puts "#{context.request.remote_address} CONNECT #{host}:#{port}"
    begin
      upstream = TCPSocket.new(host, port)

      context.response.upgrade do |downstream|
        channel = Channel(Nil).new(2)

        downstream = downstream.as(TCPSocket)
        downstream.sync = true

        spawn copy_connect(upstream, downstream, channel)
        spawn copy_connect(downstream, upstream, channel)

        2.times { channel.receive }
      end
    rescue ex : Socket::ConnectError
      Log.error { "CONNECT.Connect > #{ex.message} (#{ex.class})" }
      context.response.respond_with_status(HTTP::Status::BAD_GATEWAY, ex.message)
    rescue ex
      Log.error { "CONNECT > #{ex.message} (#{ex.class})" }
      context.response.respond_with_status(HTTP::Status::BAD_GATEWAY, ex.message)
    ensure
      context.response.close
    end
  end

  private def copy_connect(src, dst, ch)
    copy(src, dst)
  rescue IO::Error
  rescue Socket::Error
  rescue IO::TimeoutError
  rescue ex
    Log.error { "CONNECT > #{ex.message} (#{ex.class})" }
  ensure
    src.close
    dst.close
    ch.send(nil)
  end

  private def handle_http(context)
    begin
      uri = URI.parse(context.request.resource)
      puts "#{context.request.remote_address} HTTP #{uri}"
      client = HTTP::Client.new(uri)
      client.exec(context.request) do |response|
        context.response.headers.merge!(response.headers)
        context.response.status_code = response.status_code
        if response.body_io?
          copy(response.body_io, context.response.output)
          response.body_io.close
        end
      end
    rescue ex : Socket::ConnectError
      Log.error { "HTTP.CONNECT > #{ex.message} (#{ex.class})" }
      context.response.respond_with_status(HTTP::Status::BAD_GATEWAY, ex.message)
    rescue IO::Error
    rescue HTTP::Server::ClientError
    rescue ex
      host = uri ? uri.host : "nil"
      port = uri ? uri.port : 0
      Log.error { "HTTP[#{host}:#{port}] > #{ex.message} (#{ex.class})" }
      context.response.respond_with_status(HTTP::Status::BAD_GATEWAY, ex.message)
    ensure
      context.response.close
    end
  end

  COPY_BUFFER_SIZE = 8192

  # Copy of IO.copy with modified buffer size
  private def copy(src, dst) : Int64
    buffer = uninitialized UInt8[COPY_BUFFER_SIZE]
    count = 0_i64
    while (len = src.read(buffer.to_slice).to_i32) > 0
      dst.write buffer.to_slice[0, len]
      count &+= len
    end
    count
  end
end
