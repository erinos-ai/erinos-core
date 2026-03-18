require "tmpdir"
require "open-uri"

class TelegramBot
  def initialize(token: ENV.fetch("TELEGRAM_BOT_TOKEN"))
    @token = token
    @pending_links = {}
  end

  def run
    ::Telegram::Bot::Client.run(@token) do |bot|
      bot.listen do |message|
        next unless message.is_a?(::Telegram::Bot::Types::Message)
        next unless message.text || message.voice

        handle(bot, message)
      end
    end
  end

  private

  def handle(bot, message)
    telegram_id = message.from.id
    user = User.find_by(telegram_id: telegram_id)

    if user
      if message.voice
        respond_voice(bot, message, user)
      else
        respond(bot, message, user)
      end
    elsif @pending_links[telegram_id]
      link_account(bot, message, telegram_id)
    else
      request_pin(bot, message, telegram_id)
    end
  end

  def request_pin(bot, message, telegram_id)
    @pending_links[telegram_id] = true
    bot.api.send_message(
      chat_id: message.chat.id,
      text: "I don't recognize you yet. Send me your PIN to link your account."
    )
  end

  def link_account(bot, message, telegram_id)
    pin = message.text&.strip
    unless pin
      bot.api.send_message(chat_id: message.chat.id, text: "Please send your PIN as text.")
      return
    end

    user = User.find_by(pin: pin)

    if user
      user.update!(telegram_id: telegram_id)
      @pending_links.delete(telegram_id)
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "Welcome, #{user.name}!"
      )
    else
      bot.api.send_message(
        chat_id: message.chat.id,
        text: "Unknown PIN. Try again."
      )
    end
  end

  def respond(bot, message, user)
    client = ErinosClient.new(user_id: user.telegram_id)

    bot.api.send_chat_action(chat_id: message.chat.id, action: "typing")

    # Send placeholder message that we'll edit as tokens arrive
    sent = bot.api.send_message(chat_id: message.chat.id, text: "...")
    message_id = sent.is_a?(Hash) ? sent.dig("result", "message_id") : sent&.message_id

    current_text = ""
    last_edit = Time.now

    client.chat_stream(message.text) do |event, data|
      case event
      when "token"
        current_text << data["content"]

        # Split into a new message when approaching Telegram's 4096 char limit
        if current_text.length > 4000
          edit_message(bot, message.chat.id, message_id, current_text)
          sent = bot.api.send_message(chat_id: message.chat.id, text: "...")
          message_id = sent.is_a?(Hash) ? sent.dig("result", "message_id") : sent&.message_id
          current_text = ""
          last_edit = Time.now
        elsif Time.now - last_edit >= 1.0
          edit_message(bot, message.chat.id, message_id, current_text)
          last_edit = Time.now
        end
      when "done"
        edit_message(bot, message.chat.id, message_id, current_text) unless current_text.empty?
      end
    end
  rescue ErinosClient::Error => e
    text = e.message == "context_length_exceeded" ?
      "Our conversation got too long, so I've started a fresh one. Please try again." :
      "Something went wrong."

    if message_id
      edit_message(bot, message.chat.id, message_id, text)
    else
      bot.api.send_message(chat_id: message.chat.id, text: text)
    end
  end

  def edit_message(bot, chat_id, message_id, text)
    bot.api.edit_message_text(chat_id: chat_id, message_id: message_id, text: text)
  rescue Telegram::Bot::Exceptions::ResponseError
    # Telegram returns error if text hasn't changed — safe to ignore
  end

  def respond_voice(bot, message, user)
    client = ErinosClient.new(user_id: user.telegram_id)

    # Download voice file from Telegram
    file_info = bot.api.get_file(file_id: message.voice.file_id)
    file_path = file_info.file_path
    download_url = "https://api.telegram.org/file/bot#{@token}/#{file_path}"

    Dir.mktmpdir do |dir|
      ogg_path = File.join(dir, "voice.ogg")
      wav_path = File.join(dir, "voice.wav")

      # Download OGG
      URI.open(download_url) do |remote|
        File.binwrite(ogg_path, remote.read)
      end

      # Convert OGG to WAV via ffmpeg
      unless system("ffmpeg", "-i", ogg_path, "-ar", "16000", "-ac", "1", wav_path,
                     "-y", "-loglevel", "error")
        bot.api.send_message(chat_id: message.chat.id, text: "Could not process audio.")
        return
      end

      # Send to voice API, get audio response
      audio_data = client.voice(wav_path)

      # Send voice message back
      response_path = File.join(dir, "response.wav")
      File.binwrite(response_path, audio_data)

      bot.api.send_voice(
        chat_id: message.chat.id,
        voice: Faraday::UploadIO.new(response_path, "audio/wav")
      )
    end
  rescue ErinosClient::Error => e
    bot.api.send_message(
      chat_id: message.chat.id,
      text: e.message == "context_length_exceeded" ?
        "Our conversation got too long, so I've started a fresh one. Please try again." :
        "Something went wrong."
    )
  end
end
