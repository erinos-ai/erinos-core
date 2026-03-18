require "io/console"

$stdout.sync = true

class Console
  SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

  def run
    pin = authenticate
    abort "Bye!" unless pin

    @client = ErinosClient.new(user_id: pin)

    user = @client.me
    puts "\n\e[32mWelcome, #{user.dig("user", "name")}!\e[0m\n\n"

    loop do
      print "\e[36myou>\e[0m "
      input = gets
      break if input.nil?

      input = input.strip
      next if input.empty?
      break if input.downcase == "exit"

      respond(input)
    end
  rescue ErinosClient::Error => e
    abort "\e[31m#{e.message}\e[0m"
  end

  private

  def authenticate
    print "PIN (or 'new' to register): "
    input = read_pin
    return nil if input.nil? || input.empty?

    input.downcase == "new" ? register : input
  end

  def register
    print "Your name: "
    name = gets&.strip
    return nil if name.nil? || name.empty?

    print "Choose a PIN: "
    pin = read_pin
    return nil if pin.nil? || pin.empty?

    print "Confirm PIN: "
    confirmation = read_pin

    unless pin == confirmation
      puts "\e[31mPINs don't match.\e[0m"
      return nil
    end

    ErinosClient.new(user_id: "").register(name: name, pin: pin)
    pin
  rescue ErinosClient::Error => e
    puts "\e[31m#{e.message}\e[0m"
    nil
  end

  def read_pin
    pin = IO.console.getpass("")
    pin&.strip
  end

  def respond(input)
    @spinner_label = "thinking"
    @streaming = false
    @spinner = start_spinner
    first_chunk = true

    @client.chat_stream(input) do |event, data|
      case event
      when "tool_call"
        @spinner_label = data["label"]
        unless @streaming
          @spinner&.kill
          @spinner = start_spinner
        end
      when "token"
        next unless data["content"]

        if first_chunk
          @streaming = true
          @spinner&.kill
          print "\r\e[K\e[35merin>\e[0m "
          first_chunk = false
        end
        print data["content"]
      end
    end

    @spinner&.kill
    puts "\n\n"
  rescue ErinosClient::Error => e
    @spinner&.kill
    puts "\r\e[K\e[31m#{e.message}\e[0m\n\n"
  rescue Errno::ECONNREFUSED
    @spinner&.kill
    puts "\r\e[K\e[31mCannot connect to server.\e[0m\n\n"
  rescue EOFError
    @spinner&.kill
    puts "\r\e[K\e[31mConnection lost.\e[0m\n\n"
  end

  def start_spinner
    Thread.new do
      i = 0
      loop do
        print "\r\e[K\e[33m#{SPINNER_FRAMES[i % SPINNER_FRAMES.length]} #{@spinner_label}\e[0m"
        $stdout.flush
        sleep 0.1
        i += 1
      end
    end
  end
end
