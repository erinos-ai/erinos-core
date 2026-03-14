class ManageSkills < RubyLLM::Tool
  description "Install, update, list, or remove skill providers from the registry."

  param :action, desc: "One of: list_installed, list_available, install, update, update_all, remove"
  param :provider, desc: "Provider name (required for install, update, remove)", required: false

  def initialize(skill_manager:, registry:)
    @manager = skill_manager
    @registry = registry
  end

  def execute(action:, provider: nil)
    result = case action
    when "list_installed"  then format_installed(@manager.list_installed)
    when "list_available"  then format_available(@manager.list_available)
    when "install"         then require_provider!(provider) && @manager.install(provider)
    when "update"          then require_provider!(provider) && @manager.update(provider)
    when "update_all"      then @manager.update_all
    when "remove"          then require_provider!(provider) && @manager.remove(provider)
    else "Unknown action: #{action}. Use list_installed, list_available, install, update, update_all, or remove."
    end

    @registry.reload!
    result
  rescue SkillManager::Error => e
    e.message
  end

  private

  def require_provider!(provider)
    raise SkillManager::Error, "A provider name is required for this action." unless provider
    true
  end

  def format_installed(list)
    return "No skills installed." if list.empty?
    list.map { |s| "#{s[:name]} (#{s[:source]})" }.join("\n")
  end

  def format_available(list)
    return "No skills available in the registry." if list.empty?
    list.map do |s|
      status = s[:installed] ? "installed" : "not installed"
      "#{s[:name]}: #{s[:description]} [#{status}]"
    end.join("\n")
  end
end
