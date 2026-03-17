# frozen_string_literal: true

module SlashCommands
  class Base
    def initialize(user:)
      @user = user
    end

    def execute_stream(args, out)
      raise NotImplementedError
    end

    def execute(args)
      buf = StringBuffer.new
      execute_stream(args, buf)
      buf.to_s
    end

    private

    def emit_token(out, text)
      out << "event: token\ndata: #{JSON.generate(content: text)}\n\n"
    end

    def emit_progress(out, label)
      out << "event: tool_call\ndata: #{JSON.generate(name: "slash_command", label: label)}\n\n"
    end

    def emit_done(out)
      out << "event: done\ndata: {}\n\n"
    end

    def emit_lines(out, text)
      text.each_line { |line| emit_token(out, line) }
    end
  end

  # Simple string buffer for non-streaming execution
  class StringBuffer
    def initialize
      @parts = []
    end

    def <<(data)
      # Extract content from token events only
      if data.start_with?("event: token")
        json_str = data.split("data: ", 2).last.strip
        parsed = JSON.parse(json_str)
        @parts << parsed["content"] if parsed["content"]
      end
      self
    end

    def to_s
      @parts.join
    end
  end
end
