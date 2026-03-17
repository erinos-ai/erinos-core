# frozen_string_literal: true

# Server-side slash command dispatcher.
# Intercepts /commands before the LLM, runs deterministic admin flows,
# and streams output using the same SSE protocol as chat.

module SlashCommands
  COMMANDS = {
    "/help"      => Help,
    "/model"     => Model,
    "/skills"    => Skills,
    "/authorize" => Authorize,
    "/status"    => Status
  }.freeze

  def self.match?(message)
    message.strip.start_with?("/")
  end

  def self.dispatch(message, user:)
    parts = message.strip.split(/\s+/)
    command = parts.shift

    handler_class = COMMANDS[command]
    return nil unless handler_class

    handler = handler_class.new(user: user)
    args = parts
    [handler, args]
  end
end
