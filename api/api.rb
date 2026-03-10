# frozen_string_literal: true

require_relative "routes/auth"
require_relative "routes/chat"
require_relative "routes/voice"

class Api < Sinatra::Base
  set :server, :puma
  set :host_authorization, permitted: :all

  CHATS = {}
  CHAT_MUTEX = Mutex.new

  helpers do
    def current_user
      id = request.env["HTTP_X_USER_ID"]
      halt 401, json(error: "unauthorized") unless id

      user = User.find_by(pin: id) || User.find_by(telegram_id: id)
      halt 401, json(error: "unauthorized") unless user
      user
    end

    def chat_for(user)
      CHAT_MUTEX.synchronize do
        CHATS[user.id] ||= Erin.chat(user: user, channel: "api")
      end
    end

    def json(data)
      content_type :json
      data.to_json
    end

    def transcribe(audio_file)
      whisper_url = ENV.fetch("WHISPER_URL", "http://localhost:8080")
      uri = URI("#{whisper_url}/inference")

      boundary = SecureRandom.hex
      body = build_multipart(boundary, audio_file)

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = body

      response = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 120) { |http| http.request(req) }
      result = JSON.parse(response.body)
      result["text"]
    end

    def synthesize(text)
      kokoro_url = ENV.fetch("KOKORO_URL", "http://localhost:8880")
      voice = ENV.fetch("KOKORO_VOICE", "if_sara")
      uri = URI("#{kokoro_url}/v1/audio/speech")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(
        model: "kokoro",
        input: text,
        voice: voice,
        response_format: "wav"
      )

      response = Net::HTTP.start(uri.hostname, uri.port, read_timeout: 120) { |http| http.request(req) }
      return nil unless response.code == "200"
      response.body
    end

    def build_multipart(boundary, file)
      file.rewind
      data = file.read

      "--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n" \
      "Content-Type: audio/wav\r\n\r\n" \
      "#{data}\r\n" \
      "--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n" \
      "json\r\n" \
      "--#{boundary}--\r\n"
    end
  end

  register Routes::Auth
  register Routes::Chat
  register Routes::Voice

  get "/health" do
    json(status: "ok")
  end
end
