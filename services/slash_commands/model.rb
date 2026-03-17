# frozen_string_literal: true

module SlashCommands
  class Model < Base
    def execute_stream(args, out)
      case args[0]
      when nil       then show_current(out)
      when "list"    then list_models(out)
      when "switch"  then switch_model(args[1], out)
      when "pull"    then pull_model(args[1], out)
      else
        emit_token(out, "Unknown subcommand: `/model #{args[0]}`\n")
      end
    end

    private

    def show_current(out)
      model = ENV.fetch("ERIN_MODEL", "not set")
      provider = ENV.fetch("ERIN_PROVIDER", "not set")
      emit_token(out, "**Current model:** #{model} (#{provider})\n")
    end

    def list_models(out)
      emit_progress(out, "listing models")
      output, = Open3.capture2("ollama", "list")
      emit_token(out, "**Downloaded models:**\n\n")
      emit_token(out, "```\n#{output}```\n")
    end

    def switch_model(name, out)
      unless name
        emit_token(out, "Usage: `/model switch <name>`\n")
        return
      end

      env_path = "/opt/erinos/.env"
      content = File.read(env_path)
      content.sub!(/^ERIN_MODEL=.*$/, "ERIN_MODEL=#{name}")
      File.write(env_path, content)
      ENV["ERIN_MODEL"] = name

      # Clear cached chat sessions so next request uses the new model
      App::CHAT_MUTEX.synchronize { App::CHATS.clear }

      emit_token(out, "Switched to **#{name}**. New conversations will use this model.\n")
    end

    def pull_model(name, out)
      unless name
        emit_token(out, "Usage: `/model pull <name>`\n")
        return
      end

      emit_progress(out, "pulling #{name}")
      emit_token(out, "Pulling **#{name}**...\n\n")

      Open3.popen2e("ollama", "pull", name) do |_stdin, stdout_err, wait_thr|
        stdout_err.each_line do |line|
          emit_token(out, line)
        end

        unless wait_thr.value.success?
          emit_token(out, "\nFailed to pull #{name}.\n")
          return
        end
      end

      emit_token(out, "\nPulled **#{name}** successfully.\n")
    end
  end
end
