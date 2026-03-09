---
name: spotify-playback
description: "Spotify: Control music playback — play, pause, skip, queue, search."
---

# Spotify Playback

Control Spotify playback via the Web API using curl. The access token is available as `$SPOTIFY_ACCESS_TOKEN`.

## Common Headers

All requests need:

```bash
-H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN"
```

For requests with a JSON body, also add:

```bash
-H "Content-Type: application/json"
```

## Endpoints

### Get currently playing

```bash
curl -s -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  https://api.spotify.com/v1/me/player/currently-playing
```

### Play / resume

```bash
curl -s -X PUT -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  https://api.spotify.com/v1/me/player/play
```

Play a specific track or album:

```bash
curl -s -X PUT -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"uris":["spotify:track:TRACK_ID"]}' \
  https://api.spotify.com/v1/me/player/play
```

Play from context (album, playlist, artist):

```bash
curl -s -X PUT -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"context_uri":"spotify:album:ALBUM_ID"}' \
  https://api.spotify.com/v1/me/player/play
```

### Pause

```bash
curl -s -X PUT -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  https://api.spotify.com/v1/me/player/pause
```

### Next track

```bash
curl -s -X POST -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  https://api.spotify.com/v1/me/player/next
```

### Previous track

```bash
curl -s -X POST -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  https://api.spotify.com/v1/me/player/previous
```

### Add to queue

```bash
curl -s -X POST -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  "https://api.spotify.com/v1/me/player/queue?uri=spotify:track:TRACK_ID"
```

### Set volume (0-100)

```bash
curl -s -X PUT -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  "https://api.spotify.com/v1/me/player/volume?volume_percent=50"
```

### Shuffle (true/false)

```bash
curl -s -X PUT -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  "https://api.spotify.com/v1/me/player/shuffle?state=true"
```

### Repeat (track/context/off)

```bash
curl -s -X PUT -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  "https://api.spotify.com/v1/me/player/repeat?state=track"
```

### Get available devices

```bash
curl -s -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  https://api.spotify.com/v1/me/player/devices
```

### Transfer playback to a device

```bash
curl -s -X PUT -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"device_ids":["DEVICE_ID"]}' \
  https://api.spotify.com/v1/me/player
```

### Search for tracks, albums, or artists

```bash
curl -s -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  "https://api.spotify.com/v1/search?q=QUERY&type=track&limit=5"
```

Types: `track`, `album`, `artist`, `playlist`. Combine with commas: `type=track,album`.

### Recently played

```bash
curl -s -H "Authorization: Bearer $SPOTIFY_ACCESS_TOKEN" \
  "https://api.spotify.com/v1/me/player/recently-played?limit=10"
```
