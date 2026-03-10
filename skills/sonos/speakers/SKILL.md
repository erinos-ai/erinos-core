---
name: sonos-speakers
description: "Sonos: Discover speakers and groups — list, wake, volume."
---

# Sonos Speakers

Discover and manage Sonos speakers via the Sonos Control API using curl. The access token is available as `$SONOS_ACCESS_TOKEN`.

Base URL: `https://api.ws.sonos.com/control/api/v1`

## Important

Calling the Sonos API wakes speakers, making them visible to Spotify Connect.
When the user wants to redirect Spotify playback to Sonos speakers:

1. Call **list groups** (below) to wake speakers and learn their names
2. Call **Spotify get devices** — the Sonos speakers should now appear
3. Match the speaker name from Sonos to the Spotify device list
4. Transfer playback via Spotify

## Common Headers

```bash
-H "Authorization: Bearer $SONOS_ACCESS_TOKEN" -H "Content-Type: application/json"
```

## Endpoints

### List households

```bash
curl -s -H "Authorization: Bearer $SONOS_ACCESS_TOKEN" \
  https://api.ws.sonos.com/control/api/v1/households
```

Returns `{"households": [{"id": "...", ...}]}`. Most users have one household. Save the household ID for subsequent calls.

### List groups and players

```bash
curl -s -H "Authorization: Bearer $SONOS_ACCESS_TOKEN" \
  "https://api.ws.sonos.com/control/api/v1/households/HOUSEHOLD_ID/groups"
```

Returns `groups` (speaker groups) and `players` (individual speakers). Each group has an `id`, `name`, `coordinatorId`, and `playerIds`. Each player has an `id`, `name`, and `websocketUrl`.

### Get group playback status

```bash
curl -s -H "Authorization: Bearer $SONOS_ACCESS_TOKEN" \
  "https://api.ws.sonos.com/control/api/v1/groups/GROUP_ID/playback"
```

### Set group volume (0-100)

```bash
curl -s -X POST -H "Authorization: Bearer $SONOS_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"volume": 50}' \
  "https://api.ws.sonos.com/control/api/v1/groups/GROUP_ID/groupVolume"
```

### Get group volume

```bash
curl -s -H "Authorization: Bearer $SONOS_ACCESS_TOKEN" \
  "https://api.ws.sonos.com/control/api/v1/groups/GROUP_ID/groupVolume"
```

### Set player volume (0-100)

```bash
curl -s -X POST -H "Authorization: Bearer $SONOS_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"volume": 50}' \
  "https://api.ws.sonos.com/control/api/v1/players/PLAYER_ID/playerVolume"
```
