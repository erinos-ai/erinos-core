# frozen_string_literal: true

module SlashCommands
  class Status < Base
    SERVICES = %w[erinos-server ollama comfyui erinos-telegram erinos-tunnel erinos-whisper].freeze

    def execute_stream(_args, out)
      emit_token(out, "**System Status**\n\n")

      # Model
      model = ENV.fetch("ERIN_MODEL", "not set")
      emit_token(out, "Model: **#{model}**\n\n")

      # Services
      emit_token(out, "**Services:**\n\n")
      SERVICES.each do |svc|
        state, = Open3.capture2("systemctl", "is-active", svc)
        state = state.strip
        emit_token(out, "- `#{svc}` — #{state}\n")
      end

      # GPU
      gpu_busy = File.read("/sys/class/drm/card0/device/gpu_busy_percent").strip rescue "?"
      vram_used = File.read("/sys/class/drm/card0/device/mem_info_vram_used").strip.to_i rescue 0
      gtt_used = File.read("/sys/class/drm/card0/device/mem_info_gtt_used").strip.to_i rescue 0

      emit_token(out, "\n**GPU:**\n\n")
      emit_token(out, "- Usage: #{gpu_busy}%\n")
      emit_token(out, "- VRAM: #{vram_used / 1024 / 1024} MiB\n")
      emit_token(out, "- GTT: #{gtt_used / 1024 / 1024} MiB\n")
    end
  end
end
