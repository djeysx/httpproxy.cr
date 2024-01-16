require "http"

class HttpProxy::ProxyHandler
  include HTTP::Handler

  def call(context)
    begin
      case context.request.method
      when "CONNECT"
        handle_tunneling(context)
      else
        handle_http(context)
      end
    rescue ex
      Log.error { "#{context.request.method} > #{ex.message} (#{ex.class})" }
    ensure
      context.response.close
    end
  end

  private def handle_tunneling(context)
    host, port = context.request.resource.split(":", 2)
    puts "#{context.request.remote_address} CONNECT #{host}:#{port}"
    upstream : TCPSocket
    begin
      upstream = TCPSocket.new(host, port)
    rescue ex : Socket::ConnectError
      Log.error { "CONNECT.Connect > #{ex.message} (#{ex.class})" }
      context.response.respond_with_status(HTTP::Status::BAD_GATEWAY, ex.message)
      return
    end

    context.response.upgrade do |downstream|
      channel = Channel(Nil).new(2)
      downstream.as(TCPSocket).sync = true
      spawn copy_connect(upstream, downstream, channel)
      spawn copy_connect(downstream, upstream, channel)
      2.times { channel.receive }
    end
  end

  private def copy_connect(src, dst, ch)
    IO.copy(src, dst)
  rescue IO::Error
  rescue Socket::Error
  rescue IO::TimeoutError
  rescue ex
    Log.error { "CONNECT.copy > #{ex.message} (#{ex.class})" }
  ensure
    src.close
    dst.close
    ch.send(nil)
  end

  private def handle_http(context)
    begin
      request = context.request
      uri = URI.parse(request.resource)
      puts "#{request.remote_address} HTTP #{uri}"
      client = HTTP::Client.new(uri)

      srcRes : String
      if uri.query != nil
        srcRes = "#{uri.path}?#{uri.query}"
      else
        srcRes = "#{uri.path}"
      end
      request.resource = srcRes
      
      client.exec(request) do |response|
        context.response.headers.merge!(response.headers)
        context.response.status_code = response.status_code
        if response.body_io?
          IO.copy(response.body_io, context.response.output)
          response.body_io.close
        end
      end
    rescue ex : Socket::ConnectError
      Log.error { "HTTP.CONNECT > #{ex.message} (#{ex.class})" }
      context.response.respond_with_status(HTTP::Status::BAD_GATEWAY, ex.message)
    rescue IO::Error
    rescue HTTP::Server::ClientError
    end
  end
end

# Override
class HTTP::Request
  def resource=(res : String)
    @resource = res
  end
end
