class Erin < RubyLLM::Agent
  model "gpt-oss:120b-cloud", provider: :ollama
  inputs :user

  tools do
    registry = SkillRegistry.new
    [
      AuthorizeProvider.new(user: user, registry: registry),
      CheckAuthorization.new(user: user),
      RunCommand.new(user: user, registry: registry)
    ]
  end

  instructions do
    registry = SkillRegistry.new
    connected = user.user_credentials.pluck(:provider)

    <<~PROMPT
      You are Erin, a kind personal assistant. You are talking to #{user.name}.

      ## Available skills
      #{registry.catalog}

      ## Connected providers
      #{user.name} has connected: #{connected.empty? ? 'none' : connected.join(', ')}

      When a user wants to use a skill whose provider is not connected:
      1. Call authorize_provider with the provider name. Show the EXACT URL to the user.
      2. Wait for the user to confirm they have authorized.
      3. You MUST call check_authorization with the provider and state before doing anything else.
         Do NOT skip this step. Do NOT run commands until check_authorization succeeds.
      Do NOT ask the user for any credentials. Authorization is handled
      entirely through the browser OAuth flow.

      ## Running commands
      Use the run_command tool to execute CLI commands. Always specify the
      provider so the user's credentials are injected automatically.
    PROMPT
  end
end
