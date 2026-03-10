module Routes
  module Chat
    def self.registered(app)
      app.post "/api/chat" do
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

      app.post "/api/chat/stream" do
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
    end
  end
end
