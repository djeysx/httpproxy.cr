require "./httpproxy/*"
require "option_parser"

# Some overrides

# Default 32k too high for this use case.
# API lacks of parameters so I made some overrides.
# Can not override constant IO::DEFAULT_BUFFER_SIZE
# Consider manualy patch io.cr to DEFAULT_BUFFER_SIZE = 8192 to affect all IO::*
module IO::Buffered
  @buffer_size = 8192
end

abstract class IO
  COPY_BUFFER_SIZE = 8192

  def self.copy(src, dst) : Int64
    buffer = uninitialized UInt8[COPY_BUFFER_SIZE]
    count = 0_i64
    while (len = src.read(buffer.to_slice).to_i32) > 0
      dst.write buffer.to_slice[0, len]
      count &+= len
    end
    count
  end
end

# --------------------------------
def main
  bind = "::"
  port = 8080

  option_parser = OptionParser.parse do |parser|
    parser.banner = "Tiny HTTP Proxy"
    parser.on "-l LISTEN_INTERFACE", "--listen=LISTEN_INTERFACE" do |listen_interface|
      bind = listen_interface
    end
    parser.on "-p LISTEN_PORT", "--port=LISTEN_PORT" do |listen_port|
      port = listen_port.to_i32
    end
    parser.on "-h", "--help" do
      puts parser
      exit
    end
  end

  server = HTTP::Server.new([HTTP::ErrorHandler.new(verbose = true),
                             HttpProxy::ProxyHandler.new])
  address = server.bind_tcp("::", 8080)
  puts "Listening on http://#{address}"
  server.listen
end

main
