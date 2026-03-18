require "uri"
require "net/http"
require "json"

class RunCommand < RubyLLM::Tool
  description "Run a shell command. For commands that need provider credentials " \
              "(e.g. gws), specify the provider to inject the user's stored credentials."

  param :command, desc: "The shell command to run"
  param :provider, desc: "Provider name(s) to inject credentials. Comma-separated for multiple (e.g. 'rendering,google')", required: false

  def initialize(user:, registry:)
    @user = user
    @registry = registry
    @relay_url = RELAY_URL
  end

  def execute(command:, provider: nil)
    env = {}

    if provider
      provider.split(",").map(&:strip).each do |p|
        result = inject_provider(env, p)
        return result if result.is_a?(String)
      end
    end

    # Add skill script directories to PATH so skill scripts are directly callable
    skill_paths = @registry.all_skills
      .map { |s| File.join(File.dirname(s.path), "scripts") }
      .select { |d| Dir.exist?(d) }
      .uniq
    env["PATH"] = (skill_paths + [BIN_DIR, ENV["PATH"]]).join(":")

    output, status = Open3.capture2e(env, command)
    status.success? ? output : "Command failed (exit #{status.exitstatus}):\n#{output}"
  rescue Errno::ENOENT => e
    "Command not found: #{e.message}"
  end

  private

  def inject_provider(env, provider)
    skills = @registry.skills_for(provider)
    return "Unknown provider: #{provider}" if skills.empty?

    skill = skills.first
    return nil if skill.env.empty?

    credential = @user.user_credentials.find_by(provider: provider)
    return "No #{provider} credentials found. Ask the user to connect their #{provider} account first." unless credential

    refresh_if_expired!(credential, provider) if skill.auth["type"] == "oauth"

    skill.env.each { |env_var, field| env[env_var] = credential.data[field] }
    nil
  end

  def refresh_if_expired!(credential, provider)
    expires_at = credential.data["token_expires_at"]
    return unless expires_at
    return if Time.parse(expires_at) > Time.now + 60 # 60s buffer

    refresh_token = credential.data["refresh_token"]
    return unless refresh_token

    uri = URI("#{@relay_url}/oauth/refresh")
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
end
