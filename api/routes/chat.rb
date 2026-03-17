module Routes
  module Chat
    def self.registered(app)
      app.post "/api/chat" do
        user = current_user
        text = extract_message

        # Intercept slash commands before the LLM
        if SlashCommands.match?(text)
          result = SlashCommands.dispatch(text, user: user)
          if result
            handler, args = result
            content = handler.execute(args)
            return json(response: content)
          else
            return json(response: "Unknown command. Type `/help` for available commands.")
          end
        end

        return json(response: NO_MODEL_MESSAGE) unless model_configured?

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

        content_type "text/event-stream"
        headers "Cache-Control" => "no-cache"

        # Intercept slash commands before the LLM
        if SlashCommands.match?(message)
          result = SlashCommands.dispatch(message, user: user)
          if result
            handler, args = result
            stream(:keep_open) do |out|
              handler.execute_stream(args, out)
              out << "event: done\ndata: {}\n\n"
              out.close
            end
          else
            stream(:keep_open) do |out|
              out << "event: token\ndata: #{JSON.generate(content: "Unknown command. Type `/help` for available commands.\n")}\n\n"
              out << "event: done\ndata: {}\n\n"
              out.close
            end
          end
          return
        end

        unless model_configured?
          stream(:keep_open) do |out|
            out << "event: token\ndata: #{JSON.generate(content: NO_MODEL_MESSAGE)}\n\n"
            out << "event: done\ndata: {}\n\n"
            out.close
          end
          return
        end

        chat = chat_for(user)

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
        NO_MODEL_MESSAGE = <<~MD.freeze
          Hi! I'm not connected to a language model yet.

          To get started, download and activate a model:

          1. `/model pull <name>` — download a model (e.g. `qwen3:8b`)
          2. `/model switch <name>` — activate it
          3. `/model list` — see downloaded models

          Once a model is active, I'll be ready to chat!
        MD

        def model_configured?
          model = ENV.fetch("ERIN_MODEL", "")
          !model.empty?
        end

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
