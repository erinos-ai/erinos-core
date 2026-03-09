# frozen_string_literal: true

require "sinatra/base"
require "json"
require "yaml"
require "uri"
require "net/http"

class OauthRelay < Sinatra::Base
  set :host_authorization, permitted: :all

  PROVIDERS = YAML.load_file(File.expand_path("providers.yml", __dir__))
  SESSIONS = {}
  TTL = 300 # seconds

  # Called by Erin to start an OAuth flow.
  # Expects: provider, state (JSON body)
  # Returns: { url: "https://..." }
  post "/auth/start" do
    body = JSON.parse(request.body.read)
    provider = body["provider"]
    state = body["state"]

    config = PROVIDERS[provider]
    unless config
      status 400
      return json(error: "Unknown provider: #{provider}")
    end

    client_id = ENV["#{provider.upcase}_CLIENT_ID"]
    client_secret = ENV["#{provider.upcase}_CLIENT_SECRET"]

    unless client_id && client_secret
      status 400
      return json(error: "No credentials configured for provider: #{provider}")
    end

    SESSIONS[state] = {
      provider: provider,
      client_id: client_id,
      client_secret: client_secret,
      token_url: config["token_url"],
      created_at: Time.now
    }

    params = URI.encode_www_form(
      client_id: client_id,
      redirect_uri: "#{request.base_url}/callback",
      response_type: "code",
      scope: config["scopes"].join(" "),
      state: state,
      access_type: "offline",
      prompt: "consent"
    )

    cleanup_expired
    json(url: "#{config['auth_url']}?#{params}")
  end

  # OAuth callback from provider (e.g. Google).
  # Exchanges the auth code for tokens immediately.
  get "/callback" do
    state = params["state"]
    code = params["code"]
    error = params["error"]

    if error
      status 400
      return "Authorization failed: #{error}"
    end

    unless state && code
      status 400
      return "Missing state or code parameter."
    end

    session = SESSIONS[state]
    unless session
      status 400
      return "Unknown or expired session."
    end

    tokens = exchange_code(session, code, "#{request.base_url}/callback")

    if tokens["error"]
      SESSIONS.delete(state)
      status 400
      return "Token exchange failed: #{tokens['error_description'] || tokens['error']}"
    end

    SESSIONS[state] = session.merge(
      tokens: {
        access_token: tokens["access_token"],
        refresh_token: tokens["refresh_token"],
        expires_in: tokens["expires_in"]
      }
    )

    content_type :html
    <<~HTML
      <!DOCTYPE html>
      <html>
      <body style="font-family: sans-serif; text-align: center; padding-top: 100px;">
        <h2>Authorization successful</h2>
        <p>You can close this tab and return to Erin.</p>
      </body>
      </html>
    HTML
  end

  # Polled by Erin to retrieve tokens.
  get "/poll" do
    state = params["state"]

    unless state
      status 400
      return json(error: "Missing state parameter.")
    end

    session = SESSIONS[state]

    unless session&.dig(:tokens)
      status 404
      return json(status: "pending")
    end

    tokens = session[:tokens]
    SESSIONS.delete(state)
    json(status: "ok", **tokens)
  end

  # Called by Erin to refresh an expired access token.
  # Expects: provider, refresh_token (JSON body)
  # Returns: { access_token, expires_in }
  post "/auth/refresh" do
    body = JSON.parse(request.body.read)
    provider = body["provider"]

    config = PROVIDERS[provider]
    unless config
      status 400
      return json(error: "Unknown provider: #{provider}")
    end

    client_id = ENV["#{provider.upcase}_CLIENT_ID"]
    client_secret = ENV["#{provider.upcase}_CLIENT_SECRET"]

    unless client_id && client_secret
      status 400
      return json(error: "No credentials configured for provider: #{provider}")
    end

    uri = URI(config["token_url"])
    response = Net::HTTP.post_form(uri, {
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: body["refresh_token"],
      grant_type: "refresh_token"
    })

    tokens = JSON.parse(response.body)

    if tokens["error"]
      status 400
      return json(error: tokens["error_description"] || tokens["error"])
    end

    json(
      access_token: tokens["access_token"],
      expires_in: tokens["expires_in"]
    )
  end

  get "/health" do
    json(status: "ok")
  end

  private

  def json(data)
    content_type :json
    data.to_json
  end

  def exchange_code(session, code, redirect_uri)
    uri = URI(session[:token_url])
    response = Net::HTTP.post_form(uri, {
      code: code,
      client_id: session[:client_id],
      client_secret: session[:client_secret],
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    })

    JSON.parse(response.body)
  end

  def cleanup_expired
    cutoff = Time.now - TTL
    SESSIONS.delete_if { |_, v| v[:created_at] < cutoff }
  end
end
