---
name: sonos-speakers
description: "Sonos: Manage speakers — volume, grouping, playback status."
---

# Sonos Speakers

Manage Sonos speakers via the Sonos Control API using curl. The access token is available as `$SONOS_ACCESS_TOKEN`.

Base URL: `https://api.ws.sonos.com/control/api/v1`

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

### Group speakers

Create a new group by joining players to a coordinator:

```bash
curl -s -X POST -H "Authorization: Bearer $SONOS_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"playerIdsToAdd": ["PLAYER_ID_1", "PLAYER_ID_2"]}' \
  "https://api.ws.sonos.com/control/api/v1/groups/GROUP_ID/groups/modifyGroupMembers"
```

### Ungroup speakers

Remove players from a group:

```bash
curl -s -X POST -H "Authorization: Bearer $SONOS_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"playerIdsToRemove": ["PLAYER_ID"]}' \
  "https://api.ws.sonos.com/control/api/v1/groups/GROUP_ID/groups/modifyGroupMembers"
```
