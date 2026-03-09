require "json"

class StoreCredential < RubyLLM::Tool
  description "Store credentials for a provider. Use this for non-OAuth providers " \
              "(e.g. Hue bridge) after the user completes setup."

  param :provider, desc: "Provider name (e.g. 'hue')"
  param :data, desc: "JSON string of credential data (e.g. '{\"bridge_ip\":\"...\",\"api_key\":\"...\"}')"

  def initialize(user:)
    @user = user
  end

  def execute(provider:, data:)
    parsed = JSON.parse(data)
    credential = @user.user_credentials.find_or_initialize_by(provider: provider)
    credential.update!(data: (credential.data || {}).merge(parsed))
    "Credentials saved for #{provider}."
  rescue JSON::ParserError
    "Invalid JSON. Pass data as a JSON string."
  end
end
