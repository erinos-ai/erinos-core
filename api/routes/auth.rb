module Routes
  module Auth
    def self.registered(app)
      app.post "/api/auth/register" do
        body = JSON.parse(request.body.read)
        name = body["name"]&.strip
        pin = body["pin"]&.strip

        halt 400, json(error: "name and pin required") unless name&.length&.positive? && pin&.length&.positive?

        user = User.create!(name: name, pin: pin)
        json(user: { id: user.id, name: user.name })
      rescue ActiveRecord::RecordInvalid => e
        status 422
        json(error: e.message)
      end

      app.get "/api/auth/me" do
        user = current_user
        json(user: { id: user.id, name: user.name })
      end
    end
  end
end
