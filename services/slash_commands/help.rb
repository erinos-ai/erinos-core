# frozen_string_literal: true

module SlashCommands
  class Help < Base
    def execute_stream(_args, out)
      emit_token(out, "**Available commands:**\n\n")
      emit_token(out, "`/model` — Show current model\n")
      emit_token(out, "`/model list` — List downloaded models\n")
      emit_token(out, "`/model switch <name>` — Switch to a different model\n")
      emit_token(out, "`/model pull <name>` — Download a new model\n\n")
      emit_token(out, "`/skills` — List installed skills\n")
      emit_token(out, "`/skills available` — List registry skills\n")
      emit_token(out, "`/skills install <name>` — Install a skill\n")
      emit_token(out, "`/skills update` — Update all skills\n")
      emit_token(out, "`/skills remove <name>` — Remove a skill\n\n")
      emit_token(out, "`/authorize <provider>` — Start OAuth flow\n")
      emit_token(out, "`/status` — Show system status\n")
    end
  end
end
