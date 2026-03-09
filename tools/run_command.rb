require "uri"
require "net/http"
require "json"

class RunCommand < RubyLLM::Tool
  description "Run a shell command. For commands that need provider credentials " \
              "(e.g. gws), specify the provider to inject the user's stored credentials."

  param :command, desc: "The shell command to run"
  param :provider, desc: "Optional provider name to inject credentials (e.g. 'google')", required: false

  def initialize(user:, registry:)
    @user = user
    @registry = registry
    @relay_url = ENV.fetch("OAUTH_RELAY_URL", "https://oauth.erinos.ai")
  end

  def execute(command:, provider: nil)
    env = {}

    if provider
      skills = @registry.skills_for(provider)
      return "Unknown provider: #{provider}" if skills.empty?

      skill = skills.first
      credential = @user.user_credentials.find_by(provider: provider)
      return "No #{provider} credentials found. Ask the user to connect their #{provider} account first." unless credential

      refresh_if_expired!(credential, provider) if skill.auth["type"] == "oauth"

      connector = connector_for(skill.auth["type"])
      env = connector.env_for(credential.data, env_mapping: skill.env)
    end

    output, status = Open3.capture2e(env, command)
    status.success? ? output : "Command failed (exit #{status.exitstatus}):\n#{output}"
  rescue Errno::ENOENT => e
    "Command not found: #{e.message}"
  end

  private

  def refresh_if_expired!(credential, provider)
    expires_at = credential.data["token_expires_at"]
    return unless expires_at
    return if Time.parse(expires_at) > Time.now + 60 # 60s buffer

    refresh_token = credential.data["refresh_token"]
    return unless refresh_token

    uri = URI("#{@relay_url}/auth/refresh")
    response = Net::HTTP.post(uri, {
      provider: provider,
      refresh_token: refresh_token
    }.to_json, "Content-Type" => "application/json")

    body = JSON.parse(response.body)
    return if body["error"]

    credential.update!(data: credential.data.merge(
      "access_token" => body["access_token"],
      "token_expires_at" => (Time.now + body["expires_in"].to_i).iso8601
    ))
  end

  def connector_for(type)
    case type
    when "oauth" then Connectors::Oauth
    else raise "Unknown connector type: #{type}"
    end
  end
end
