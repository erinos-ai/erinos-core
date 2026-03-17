class Erin < RubyLLM::Agent
  REGISTRY      = SkillRegistry.new
  SKILL_MANAGER = SkillManager.new
  PROMPT = File.read(File.expand_path("../prompts/erin.md.erb", __dir__))

  model ENV.fetch("ERIN_MODEL"), provider: ENV.fetch("ERIN_PROVIDER").to_sym
  inputs :user, :channel

  tools do
    [
      AuthorizeProvider.new(user: user, registry: REGISTRY),
      CheckAuthorization.new(user: user),
      StoreCredential.new(user: user),
      ReadSkill.new(registry: REGISTRY),
      RunCommand.new(user: user, registry: REGISTRY),
      ManageSchedule.new(user: user, channel: channel),
      ManageMemory.new(user: user),
      ManageSkills.new(skill_manager: SKILL_MANAGER, registry: REGISTRY)
    ]
  end

  instructions do
    connected = user.user_credentials.pluck(:provider)
    memories = user.memories.order(:created_at).pluck(:id, :content)
    memories_text = if memories.empty?
                      "None yet."
                    else
                      memories.map { |id, content| "- #{content} (##{id})" }.join("\n")
                    end
    catalog = REGISTRY.catalog

    ERB.new(PROMPT).result(binding)
  end
end
