require "io/console"

class Gateway
  attr_reader :current_user

  def self.enter
    gateway = new
    user = gateway.authenticate
    abort "Bye!" unless user

    puts "\n\e[32mWelcome, #{user.name}!\e[0m\n\n"
    user
  end

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

  private

  def login(pin)
    user = User.find_by(pin: pin)

    if user
      @current_user = user
    else
      puts "\e[31mUnknown PIN.\e[0m"
      nil
    end
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

    @current_user = User.create!(name: name, pin: pin)
  rescue ActiveRecord::RecordInvalid => e
    puts e.message
    nil
  end

  def read_pin
    pin = IO.console.getpass("")
    pin&.strip
  end
end
