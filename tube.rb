require 'socket'
require 'http/parser'
require 'stringio'

class Tube
  def initialize(port, app)
    @app = app
    @server = TCPServer.new(port)
  end

  def start
    loop do
      connection = Connection.new(@server.accept, @app)
      connection.process
    end
    socket = @server.accept

  end

  class Connection
    REASONS = {
      200 => "OK"
    }.freeze

    def initialize(socket, app)
      @socket = socket
      @app = app
      @parser = Http::Parser.new(self)
    end

    def process
      until @socket.closed? || @socket.eof?
        data = @socket.readpartial(1024)
        @parser << data
      end
    end

    def on_message_complete
      puts "#{@parser.http_method} #{@parser.request_path}"
      puts " " + @parser.headers.inspect
      puts

      env = {}
      @parser.headers.each_pair do |name, value|
        #User-Agent => HTTP_USER_AGENT
        env["HTTP_#{name.upcase.tr('-','_')}"] = value
      end

      env["PATH_INFO"] = @parser.request_path
      env["REQUEST_METHOD"] = @parser.http_method
      env["rack.input"] = StringIO.new

      send_response env
    end
    
    def send_response(env)
      status, headers, body = @app.call(env)
      reason = REASONS[status]
      @socket.write "HTTP/1.1 #{status} #{reason}"
      @socket.write carriage_return

      headers.each_pair do |name, value|
        @socket.write "#{name.to_s}: #{value.to_s}"
        @socket.write carriage_return
      end

      @socket.write carriage_return

      body.each do |content|
        @socket.write content.to_s
      end.join

      body.close if body.responds_to? :close

      @socket.write carriage_return

      close
    end

    def carriage_return
      "\r\n"
    end

    def close
      @socket.close
    end
  end
end

class App
  def call(env)
    sleep 5 if env["PATH_INFO"] == "/sleep"

    message = "Hello from the tube.\n"
    [
      200,
      { 'Content-Type' => 'text/plain', 'Content-Length' => message.size.to_s },
      [message]
    ]
  end
end

server = Tube.new(3000, App.new)
puts "Opening the tube"
server.start

