---
name: hue-lights
description: "Philips Hue: Control lights — on/off, brightness, color, scenes."
---

# Philips Hue Lights

Control Hue lights via the local bridge API (CLIP v2) using curl. The bridge IP and API key are available as `$HUE_BRIDGE_IP` and `$HUE_API_KEY`.

All requests use HTTPS with `-k` (the bridge uses a self-signed certificate).

## Setup

If not connected, guide the user through these steps:

1. Discover the bridge:

```bash
curl -s https://discovery.meethue.com
```

2. Ask the user to press the button on their Hue bridge.

3. Create an API key:

```bash
curl -s -k -X POST "https://BRIDGE_IP/api" \
  -d '{"devicetype":"erinos#device","generateclientkey":true}'
```

4. Store the `bridge_ip` and `api_key` (username from response) using store_credential.

## Common Headers

```bash
-k -H "hue-application-key: $HUE_API_KEY"
```

## Endpoints

### List all lights

```bash
curl -s -k -H "hue-application-key: $HUE_API_KEY" \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/light"
```

### Get a single light

```bash
curl -s -k -H "hue-application-key: $HUE_API_KEY" \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/light/LIGHT_ID"
```

### Turn on/off

```bash
curl -s -k -X PUT -H "hue-application-key: $HUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"on":{"on":true}}' \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/light/LIGHT_ID"
```

### Set brightness (0-100)

```bash
curl -s -k -X PUT -H "hue-application-key: $HUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"dimming":{"brightness":80}}' \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/light/LIGHT_ID"
```

### Set color (CIE xy)

```bash
curl -s -k -X PUT -H "hue-application-key: $HUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"color":{"xy":{"x":0.3, "y":0.3}}}' \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/light/LIGHT_ID"
```

Common colors (xy): red `0.68, 0.31` · green `0.21, 0.71` · blue `0.15, 0.06` · warm white `0.45, 0.41` · cool white `0.31, 0.33`

### Set color temperature (mirek, 153-500)

```bash
curl -s -k -X PUT -H "hue-application-key: $HUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"color_temperature":{"mirek":250}}' \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/light/LIGHT_ID"
```

153 = coolest (6500K), 500 = warmest (2000K)

### List rooms/zones

```bash
curl -s -k -H "hue-application-key: $HUE_API_KEY" \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/room"
```

### List scenes

```bash
curl -s -k -H "hue-application-key: $HUE_API_KEY" \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/scene"
```

### Activate a scene

```bash
curl -s -k -X PUT -H "hue-application-key: $HUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"recall":{"action":"active"}}' \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/scene/SCENE_ID"
```

### Control a group (room/zone)

```bash
curl -s -k -X PUT -H "hue-application-key: $HUE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"on":{"on":true},"dimming":{"brightness":50}}' \
  "https://$HUE_BRIDGE_IP/clip/v2/resource/grouped_light/GROUP_ID"
```
