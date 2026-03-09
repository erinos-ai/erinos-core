require "io/console"

class Console
  SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

  def run
    user = authenticate
    abort "Bye!" unless user

    puts "\n\e[32mWelcome, #{user.name}!\e[0m\n\n"

    chat = Erin.chat(user: user)

    loop do
      print "\e[36myou>\e[0m "
      input = gets
      break if input.nil?

      input = input.strip
      next if input.empty?
      break if input.downcase == "exit"

      respond(chat, input)
    end
  end

  private

  def authenticate
    print "PIN (or 'new' to register): "
    input = read_pin
    return nil if input.nil? || input.empty?

    if input.downcase == "new"
      register
    else
      login(input)
    end
  end

  def login(pin)
    user = User.find_by(pin: pin)

    unless user
      puts "\e[31mUnknown PIN.\e[0m"
      return nil
    end

    user
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

    User.create!(name: name, pin: pin)
  rescue ActiveRecord::RecordInvalid => e
    puts e.message
    nil
  end

  def read_pin
    pin = IO.console.getpass("")
    pin&.strip
  end

  def respond(chat, input)
    spinner = start_spinner

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

  def start_spinner
    Thread.new do
      i = 0
      loop do
        print "\r\e[33m#{SPINNER_FRAMES[i % SPINNER_FRAMES.length]} thinking...\e[0m"
        sleep 0.1
        i += 1
      end
    end
  end
end
