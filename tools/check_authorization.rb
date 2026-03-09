require "uri"
require "net/http"
require "json"

class CheckAuthorization < RubyLLM::Tool
  description "Check if the user has completed OAuth authorization. " \
              "Call this after the user says they have authorized."

  param :provider, desc: "Provider name (e.g. 'google')"
  param :state, desc: "The state token from authorize_provider"

  POLL_INTERVAL = 3
  POLL_TIMEOUT = 120

  def initialize(user:)
    @user = user
    @relay_url = ENV.fetch("OAUTH_RELAY_URL", "https://oauth.erinos.ai")
  end

  def execute(provider:, state:)
    tokens = poll_for_tokens(state)
    return "Authorization not completed yet. Ask the user to open the URL and try again." unless tokens

    credential = @user.user_credentials.find_or_initialize_by(provider: provider)
    credential.update!(data: (credential.data || {}).merge(
      "access_token" => tokens["access_token"],
      "refresh_token" => tokens["refresh_token"],
      "token_expires_at" => (Time.now + tokens["expires_in"].to_i).iso8601
    ))

    "Authorization successful! Your #{provider} account is now connected."
  end

  private

  def poll_for_tokens(state)
    deadline = Time.now + POLL_TIMEOUT

    while Time.now < deadline
      sleep POLL_INTERVAL

      uri = URI("#{@relay_url}/poll?state=#{state}")
      response = Net::HTTP.get_response(uri)

      if response.code == "200"
        body = JSON.parse(response.body)
        return body if body["status"] == "ok"
      end
    end

    nil
  end
end
