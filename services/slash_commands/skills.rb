# frozen_string_literal: true

module SlashCommands
  class Skills < Base
    def execute_stream(args, out)
      case args[0]
      when nil         then list_installed(out)
      when "available" then list_available(out)
      when "install"   then install_skill(args[1], out)
      when "update"    then update_skills(out)
      when "remove"    then remove_skill(args[1], out)
      else
        emit_token(out, "Unknown subcommand: `/skills #{args[0]}`\n")
      end
    rescue SkillManager::Error => e
      emit_token(out, "Error: #{e.message}\n")
    end

    private

    def skill_manager
      @skill_manager ||= SkillManager.new
    end

    def list_installed(out)
      installed = skill_manager.list_installed
      if installed.empty?
        emit_token(out, "No skills installed.\n")
        return
      end

      emit_token(out, "**Installed skills:**\n\n")
      installed.each do |s|
        source = s[:source] == "registry" ? " *(registry)*" : ""
        emit_token(out, "- #{s[:name]}#{source}\n")
      end
    end

    def list_available(out)
      emit_progress(out, "fetching registry")
      available = skill_manager.list_available

      emit_token(out, "**Available skills:**\n\n")
      available.each do |s|
        status = s[:installed] ? "installed" : "not installed"
        line = "- **#{s[:name]}** — #{status}"
        line += "\n  #{s[:description][0..80]}" if s[:description]
        emit_token(out, "#{line}\n")
      end
    end

    def install_skill(name, out)
      unless name
        emit_token(out, "Usage: `/skills install <name>`\n")
        return
      end

      emit_progress(out, "installing #{name}")
      result = skill_manager.install(name)

      # Run setup script if present (before reporting success)
      run_setup_script(name, out)

      Erin::REGISTRY.reload!
      emit_token(out, "#{result}\n")
    end

    def update_skills(out)
      emit_progress(out, "updating skills")
      result = skill_manager.update_all
      Erin::REGISTRY.reload!
      emit_token(out, "#{result}\n")
    end

    def remove_skill(name, out)
      unless name
        emit_token(out, "Usage: `/skills remove <name>`\n")
        return
      end

      emit_progress(out, "removing #{name}")
      result = skill_manager.remove(name)
      Erin::REGISTRY.reload!
      emit_token(out, "#{result}\n")
    end

    def run_setup_script(provider, out)
      skills_dir = ENV.fetch("SKILLS_DIR", SkillManager::DEFAULT_DIR)
      provider_dir = File.join(skills_dir, provider)
      setup_script = File.join(provider_dir, "scripts", "setup")

      return unless File.executable?(setup_script)

      emit_token(out, "\nRunning setup for **#{provider}**...\n\n")
      emit_progress(out, "running setup")

      env = { "BIN_DIR" => BIN_DIR }
      Open3.popen2e(env, setup_script, provider_dir) do |_stdin, stdout_err, wait_thr|
        stdout_err.each_line do |line|
          emit_token(out, line)
        end

        unless wait_thr.value.success?
          emit_token(out, "\nSetup script failed.\n")
          return
        end
      end

      emit_token(out, "\nSetup complete.\n")
    end
  end
end
