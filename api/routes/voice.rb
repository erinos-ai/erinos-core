module Routes
  module Voice
    def self.registered(app)
      app.post "/api/voice" do
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
    end
  end
end
