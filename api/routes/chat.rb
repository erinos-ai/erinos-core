module Routes
  module Chat
    def self.registered(app)
      app.post "/api/chat" do
        user = current_user
        text = extract_message
        chat = chat_for(user)
        response = chat.ask(text)
        respond_with(response.content)
      rescue RubyLLM::ContextLengthExceededError
        handle_context_overflow(user)
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
        handle_context_overflow(user)
      end

      app.helpers do
        def extract_message
          if params[:file]
            text = transcribe(params[:file][:tempfile])
            halt 400, json(error: "could not transcribe audio") if text.nil? || text.strip.empty?
            text
          else
            body = JSON.parse(request.body.read)
            text = body["message"]
            halt 400, json(error: "message required") unless text&.strip&.length&.positive?
            text
          end
        end

        def respond_with(text)
          if params[:file] || request.env["HTTP_ACCEPT"]&.include?("audio/wav")
            audio_data = synthesize(text)
            halt 502, json(error: "TTS failed") unless audio_data
            content_type "audio/wav"
            audio_data
          else
            json(response: text)
          end
        end
      end
    end
  end
end
