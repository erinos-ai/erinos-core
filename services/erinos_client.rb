require "net/http"
require "json"
require "uri"
require "securerandom"

class ErinosClient
  def initialize(base_url: "http://localhost:4567", user_id:)
    @base_url = base_url
    @user_id = user_id.to_s
  end

  def me
    get("/api/auth/me")
  end

  def chat(message)
    post("/api/chat", message: message)
  end

  def chat_stream(message, &block)
    uri = URI("#{@base_url}/api/chat/stream")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["X-User-ID"] = @user_id
    req.body = JSON.generate(message: message)

    Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req) do |response|
        unless response.code == "200"
          body = JSON.parse(response.body) rescue {}
          raise Error.new(response.code, body["error"] || "Request failed")
        end

        buffer = ""
        response.read_body do |chunk|
          buffer << chunk
          while (line_end = buffer.index("\n\n"))
            frame = buffer.slice!(0, line_end + 2)
            event, data = parse_sse(frame)
            block.call(event, data) if event && data
          end
        end
      end
    end
  end

  def voice(file_path)
    uri = URI("#{@base_url}/api/chat")
    boundary = SecureRandom.hex

    file_data = File.binread(file_path)
    body = "--#{boundary}\r\n" \
           "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(file_path)}\"\r\n" \
           "Content-Type: audio/wav\r\n\r\n" \
           "#{file_data}\r\n" \
           "--#{boundary}--\r\n"

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    req["X-User-ID"] = @user_id
    req.body = body

    response = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 300) { |http| http.request(req) }
    unless response.code == "200"
      error = (JSON.parse(response.body)["error"] rescue "Voice request failed")
      raise Error.new(response.code, error)
    end
    response.body
  end

  def register(name:, pin:)
    uri = URI("#{@base_url}/api/auth/register")
    response = Net::HTTP.post(uri, JSON.generate(name: name, pin: pin), "Content-Type" => "application/json")
    body = JSON.parse(response.body)
    raise Error.new(response.code, body["error"]) unless response.code == "200"
    body
  end

  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  private

  def get(path)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Get.new(uri)
    req["X-User-ID"] = @user_id

    response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }
    body = JSON.parse(response.body)
    raise Error.new(response.code, body["error"]) unless response.code == "200"
    body
  end

  def post(path, data)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["X-User-ID"] = @user_id
    req.body = JSON.generate(data)

    response = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 300) { |http| http.request(req) }
    body = JSON.parse(response.body)
    raise Error.new(response.code, body["error"]) unless response.code == "200"
    body
  end

  def parse_sse(frame)
    event = nil
    data = nil

    frame.each_line do |line|
      line = line.strip
      if line.start_with?("event: ")
        event = line.sub("event: ", "")
      elsif line.start_with?("data: ")
        data = JSON.parse(line.sub("data: ", ""))
      end
    end

    [event, data]
  end
end
