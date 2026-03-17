# frozen_string_literal: true

module SlashCommands
  class Authorize < Base
    POLL_INTERVAL = 5
    POLL_TIMEOUT  = 300 # 5 minutes

    def execute_stream(args, out)
      provider = args[0]
      unless provider
        emit_token(out, "Usage: `/authorize <provider>`\n\nExample: `/authorize google`\n")
        return
      end

      state = SecureRandom.hex(16)
      relay_url = RELAY_URL

      emit_progress(out, "starting OAuth for #{provider}")

      # Request auth URL from relay
      uri = URI("#{relay_url}/oauth/start")
      response = Net::HTTP.post(uri, { provider: provider, state: state }.to_json,
        "Content-Type" => "application/json")
      body = JSON.parse(response.body)

      if body["error"]
        emit_token(out, "Error: #{body["error"]}\n")
        return
      end

      emit_token(out, "Open this URL in your browser:\n\n#{body["url"]}\n\n")
      emit_progress(out, "waiting for authorization")

      # Poll for tokens
      tokens = poll_for_tokens(relay_url, state, out)

      unless tokens
        emit_token(out, "Authorization timed out.\n")
        return
      end

      # Store credentials
      credential = UserCredential.find_or_initialize_by(user_id: @user.id, provider: provider)
      credential.update!(data: {
        "access_token" => tokens["access_token"],
        "refresh_token" => tokens["refresh_token"],
        "token_expires_at" => (Time.now + tokens["expires_in"].to_i).iso8601
      })

      emit_token(out, "**#{provider.capitalize}** connected successfully!\n")
    rescue => e
      emit_token(out, "Error: #{e.message}\n")
    end

    private

    def poll_for_tokens(relay_url, state, out)
      polls = POLL_TIMEOUT / POLL_INTERVAL

      polls.times do
        sleep POLL_INTERVAL
        poll_uri = URI("#{relay_url}/oauth/poll?state=#{state}")
        poll_response = Net::HTTP.get_response(poll_uri)
        poll_body = JSON.parse(poll_response.body)

        return poll_body if poll_body["status"] == "ok"

        emit_token(out, ".")
      end

      nil
    end
  end
end
