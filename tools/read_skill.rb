class ReadSkill < RubyLLM::Tool
  description "Read a skill's full documentation. Call this before running " \
              "commands for a skill to learn the correct syntax and available operations."

  param :skill, desc: "Skill name (e.g. 'spotify-playback', 'gws-calendar')"

  def initialize(registry:)
    @registry = registry
  end

  def execute(skill:)
    body = @registry.skill_body(skill)
    body || "Unknown skill: #{skill}"
  end
end
