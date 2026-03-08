class Erin < RubyLLM::Agent
  SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

  model "gpt-oss:120b-cloud", provider: :ollama
  inputs :user
  instructions { "You are a kind personal assistant. You are talking to #{user.name}." }

  def self.run(user:)
    chat = self.chat(user: user)

    loop do
      print "\e[36myou>\e[0m "
      input = gets
      break if input.nil?

      input = input.strip
      next if input.empty?
      break if input.downcase == "exit"

      spinner = Thread.new do
        i = 0
        loop do
          print "\r\e[33m#{SPINNER_FRAMES[i % SPINNER_FRAMES.length]} thinking...\e[0m"
          sleep 0.1
          i += 1
        end
      end

      first_chunk = true
      chat.ask(input) do |chunk|
        if first_chunk
          spinner.kill
          print "\r\e[35merin>\e[0m "
          first_chunk = false
        end
        print chunk.content
      end

      puts "\n\n"
    end
  end
end
