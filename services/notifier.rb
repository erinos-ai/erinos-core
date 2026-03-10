class Notifier
  def self.send(user:, channel:, text:)
    case channel
    when "telegram"
      send_telegram(user, text)
    else
      puts "[notifier] No outbound support for channel: #{channel}"
    end
  end

  def self.send_telegram(user, text)
    token = ENV.fetch("TELEGRAM_BOT_TOKEN")
    chat_id = user.telegram_id

    unless chat_id
      puts "[notifier] User #{user.name} has no telegram_id"
      return
    end

    api = ::Telegram::Bot::Api.new(token)
    api.send_message(chat_id: chat_id, text: text)
  end
end
