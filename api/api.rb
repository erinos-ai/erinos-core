# frozen_string_literal: true

class Api < Sinatra::Base
  set :server, :puma
  set :host_authorization, permitted: :all

  CHATS = {}
  CHAT_MUTEX = Mutex.new

  # --- Auth ---

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

  # --- Routes ---

  post "/api/chat" do
    user = current_user
    body = JSON.parse(request.body.read)
    message = body["message"]
    halt 400, json(error: "message required") unless message&.strip&.length&.positive?

    chat = chat_for(user)
    response = chat.ask(message)
    json(response: response.content)
  rescue RubyLLM::ContextLengthExceededError
    CHAT_MUTEX.synchronize { CHATS.delete(user.id) }
    status 400
    json(error: "context_length_exceeded")
  end

  post "/api/chat/stream" do
    user = current_user
    body = JSON.parse(request.body.read)
    message = body["message"]
    halt 400, json(error: "message required") unless message&.strip&.length&.positive?

    chat = chat_for(user)

    content_type "text/event-stream"
    headers "Cache-Control" => "no-cache"

    stream(:keep_open) do |out|
      chat.on_tool_call do |tool_call|
        label = tool_call.arguments["provider"] || tool_call.arguments["skill"] || tool_call.arguments["action"] || tool_call.name
        out << "event: tool_call\ndata: #{JSON.generate(name: tool_call.name, label: label)}\n\n"
      end

      chat.ask(message) do |chunk|
        next if chunk.content.nil? || chunk.content.empty?
        out << "event: token\ndata: #{JSON.generate(content: chunk.content)}\n\n"
      end

      out << "event: done\ndata: {}\n\n"
      out.close
    end
  rescue RubyLLM::ContextLengthExceededError
    CHAT_MUTEX.synchronize { CHATS.delete(user.id) }
    status 400
    json(error: "context_length_exceeded")
  end

  post "/api/auth/register" do
    body = JSON.parse(request.body.read)
    name = body["name"]&.strip
    pin = body["pin"]&.strip

    halt 400, json(error: "name and pin required") unless name&.length&.positive? && pin&.length&.positive?

    user = User.create!(name: name, pin: pin)
    json(user: { id: user.id, name: user.name })
  rescue ActiveRecord::RecordInvalid => e
    status 422
    json(error: e.message)
  end

  post "/api/voice" do
    user = current_user
    audio = params[:file]
    halt 400, json(error: "audio file required") unless audio

    # STT: whisper
    text = transcribe(audio[:tempfile])
    halt 400, json(error: "could not transcribe audio") if text.nil? || text.strip.empty?

    # Chat: Erin
    chat = chat_for(user)
    response = chat.ask(text)

    # TTS: Kokoro
    audio_data = synthesize(response.content)
    halt 502, json(error: "TTS failed") unless audio_data

    content_type "audio/wav"
    audio_data
  rescue RubyLLM::ContextLengthExceededError
    CHAT_MUTEX.synchronize { CHATS.delete(user.id) }
    status 400
    json(error: "context_length_exceeded")
  end

  get "/api/auth/me" do
    user = current_user
    json(user: { id: user.id, name: user.name })
  end

  get "/health" do
    json(status: "ok")
  end

  private

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
