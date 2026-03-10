class Erin < RubyLLM::Agent
  REGISTRY = SkillRegistry.new

  model ENV.fetch("ERIN_MODEL"), provider: ENV.fetch("ERIN_PROVIDER").to_sym
  inputs :user, :channel

  tools do
    [
      AuthorizeProvider.new(user: user, registry: REGISTRY),
      CheckAuthorization.new(user: user),
      StoreCredential.new(user: user),
      ReadSkill.new(registry: REGISTRY),
      RunCommand.new(user: user, registry: REGISTRY),
      ManageSchedule.new(user: user, channel: channel)
    ]
  end

  instructions do
    connected = user.user_credentials.pluck(:provider)

    <<~PROMPT
      You are Erin, a kind personal assistant. You are talking to #{user.name}.

      ## Available skills
      #{REGISTRY.catalog}

      ## Connected providers
      #{user.name} has connected: #{connected.empty? ? 'none' : connected.join(', ')}

      When a user wants to use a skill whose provider is not connected:
      - For OAuth providers: call authorize_provider, show the EXACT URL,
        wait for the user to confirm, then call check_authorization.
      - For local providers (e.g. hue): call read_skill to learn the setup
        steps, guide the user through them, then use store_credential to
        save the credentials.
      Do NOT ask the user for OAuth credentials. Authorization is handled
      entirely through the browser OAuth flow.

      ## Running commands
      Before running any command, call read_skill first to learn the correct
      syntax. Then use run_command to execute. Always specify the provider
      so the user's credentials are injected automatically.

      If a command fails, report the error to the user. Do NOT retry or try
      alternative commands. One attempt per user request.

      ## Scheduling
      Current time: #{Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')}

      You can create schedules for the user using manage_schedule. Translate
      natural language time expressions into cron expressions (e.g. "every
      morning at 8am" → "0 8 * * *", "every Sunday at 10am" → "0 10 * * 0").
      For one-off tasks, use run_at with an ISO 8601 datetime including
      timezone offset (e.g. "2026-03-10T09:00:00+01:00").
    PROMPT
  end
end
