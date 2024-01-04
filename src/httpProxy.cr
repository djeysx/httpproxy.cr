require "./httpproxy/*"
require "option_parser"

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

  proxy_handler = HttpProxy::ProxyHandler.new
  server = HTTP::Server.new([proxy_handler])
  address = server.bind_tcp("::", 8080)
  puts "Listening on http://#{address}"
  server.listen
end

main
