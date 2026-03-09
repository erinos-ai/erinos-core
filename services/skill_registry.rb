require "yaml"

class SkillRegistry
  Skill = Data.define(:name, :description, :provider, :auth, :env, :path)

  def initialize(skills_dir: File.expand_path("../skills", __dir__))
    @skills_dir = skills_dir
    @skills = {}
    load_all
  end

  def all_skills
    @skills.values
  end

  def find_skill(name)
    @skills[name]
  end

  def skills_for(provider_name)
    @skills.values.select { |s| s.provider == provider_name }
  end

  def providers
    @skills.values.map(&:provider).uniq
  end

  def catalog
    @skills.values.group_by(&:provider).map do |provider, skills|
      lines = skills.map { |s| "  - #{s.name}: #{s.description}" }
      "#{provider}:\n#{lines.join("\n")}"
    end.join("\n\n")
  end

  def skill_body(name)
    skill = find_skill(name)
    return nil unless skill

    content = File.read(skill.path)
    content.sub(/\A---\n.*?^---\n/m, "").strip
  end

  private

  def load_all
    Dir[File.join(@skills_dir, "*/provider.yml")].each do |provider_path|
      provider_dir = File.dirname(provider_path)
      provider_name = File.basename(provider_dir)
      provider_config = YAML.safe_load_file(provider_path)

      Dir[File.join(provider_dir, "*/SKILL.md")].each do |path|
        frontmatter = parse_frontmatter(path)
        next unless frontmatter

        @skills[frontmatter["name"]] = Skill.new(
          name: frontmatter["name"],
          description: frontmatter["description"],
          provider: provider_name,
          auth: provider_config["auth"] || {},
          env: provider_config["env"] || {},
          path: path
        )
      end
    end
  end

  def parse_frontmatter(path)
    content = File.read(path)
    match = content.match(/\A---\n(.*?)^---\n/m)
    return nil unless match

    YAML.safe_load(match[1], permitted_classes: [Symbol])
  end
end
