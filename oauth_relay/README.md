# OAuth Relay

Shared OAuth relay for ErinOS appliances. Holds provider client credentials and handles the OAuth flow so individual appliances never need client secrets.

## How it works

1. Erin calls `/auth/start` with a provider name — the relay builds the OAuth URL using its stored client credentials
2. The user authorizes in their browser — the provider redirects to `/callback` where the relay exchanges the code for tokens
3. Erin polls `/poll` to retrieve the tokens and stores them locally
4. When tokens expire, Erin calls `/auth/refresh` — the relay uses the client secret to get a new access token

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/start` | Start an OAuth flow (expects `provider`, `state`) |
| GET | `/callback` | OAuth callback from provider |
| GET | `/poll` | Poll for tokens (expects `state`) |
| POST | `/auth/refresh` | Refresh an expired token (expects `provider`, `refresh_token`) |
| GET | `/health` | Health check |

## Adding a provider

1. Add the provider's OAuth config to `providers.yml`
2. Add `PROVIDER_CLIENT_ID` and `PROVIDER_CLIENT_SECRET` to `.env`
3. Redeploy

## Deploy to Fly.io

```
cp .env.example .env   # fill in HOST and client credentials
./deploy.sh
```

On first run, the script launches the app and adds a TLS certificate for your `HOST` domain. Add the CNAME record Fly gives you to your DNS. Subsequent runs update secrets and redeploy.
