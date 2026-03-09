require "securerandom"
require "uri"
require "net/http"
require "json"

class AuthorizeProvider < RubyLLM::Tool
  description "Start the OAuth authorization flow for a provider. " \
              "Returns a URL for the user to open in their browser. " \
              "After the user opens the URL and authorizes, call check_authorization to complete the flow."

  param :provider, desc: "Provider name (e.g. 'google')"

  def initialize(user:, registry:)
    @user = user
    @registry = registry
    @relay_url = ENV.fetch("OAUTH_RELAY_URL", "https://oauth.erinos.ai")
  end

  def execute(provider:)
    skills = @registry.skills_for(provider)
    return "Unknown provider: #{provider}" if skills.empty?

    skill = skills.first
    return "Provider #{provider} does not support OAuth." unless skill.auth["type"] == "oauth"

    state = SecureRandom.hex(16)
    uri = URI("#{@relay_url}/auth/start")
    response = Net::HTTP.post(
      uri,
      { provider: provider, state: state }.to_json,
      "Content-Type" => "application/json"
    )

    body = JSON.parse(response.body)
    return "Error: #{body['error']}" if body["error"]

    "IMPORTANT: Show this EXACT URL to the user, do not summarize or omit it.\n\n#{body['url']}\n\nOnce the user confirms they have authorized, call check_authorization with provider: #{provider}, state: #{state}"
  end
end
