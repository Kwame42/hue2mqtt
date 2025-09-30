# HUE2MQTT Calaos Integration Guide

This guide explains how to integrate Philips Hue devices with the Calaos home automation system using HUE2MQTT as a bridge.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Simple Setup (Less than 5 devices)](#simple-setup)
3. [Advanced Setup (Multiple devices with rooms and zones)](#advanced-setup)
4. [Migration from Legacy HUE2MQTT](#migration-legacy)
5. [Configuration Examples](#configuration-examples)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites {#prerequisites}

Before starting the integration, ensure you have:

- **Calaos OS** installed and running
- **Philips Hue Bridge** connected to your network
- **HUE2MQTT** installed and configured
- **MQTT broker** (Mosquitto) enabled in Calaos

### Enable Mosquitto in Calaos

Mosquitto is already integrated into Calaos OS. Enable it with:

```bash
ssh root@your-calaos-server.local
systemctl enable --now mosquitto
```

```bash
systemctl restart mosquitto
```

---

## Simple Setup (Less than 5 devices) {#simple-setup}

For basic setups with a few Hue devices, you can use the simplified configuration approach.

### Quick Start

For detailed step-by-step instructions for simple setups, please visit:

**📖 [Complete Simple Setup Guide](https://monexample.com)**

This external resource provides:
- Basic Hue bridge configuration
- MQTT broker setup
- Simple device integration
- Basic automation examples

The simple setup is perfect for:
- Single room installations
- Basic on/off lighting control  
- Getting started with Hue automation
- Testing the integration

---

## Advanced Setup (Multiple devices with rooms and zones) {#advanced-setup}
**⚠️ Advanced Users Only**: This section is for experienced Calaos administrators who want to upgrade from an older HUE2MQTT implementation to the new Elixir-based version.

## Migration from Legacy HUE2MQTT {#migration-legacy}

We provide a fully retro-compatible implementation of the hue2mqtt Python version to replace with a new version.

To do so, log into your Calaos system using SSH and backup the file:

```bash
cp /usr/share/calaos/calaos-hue2mqtt.source /usr/share/calaos/calaos-hue2mqtt.source.backup.$(date +%Y%m%d_%H%M%S)
```

Replace it with new content:

```bash
cat > /usr/share/calaos/calaos-hue2mqtt.source
IMAGE_SRC=docker.io/kwame42/hue2mqtt:latest
COMMAND="mix hue.mqtt.server --toml-config /config/config.toml"
SERVICE_NAME=hue2mqtt.service
```

Restart your Calaos hue2mqtt service:
```bash
systemctl restart hue2mqtt
```

### Overview

For complex installations with multiple devices, rooms, and zones, follow this comprehensive setup process.

### Step 1: Organize Your Hue Devices

Before setting up the MQTT integration, properly organize your Hue devices using the official Philips Hue app.

#### 1.1 Create Rooms in Hue App

Open the Philips Hue app and organize your devices into rooms:

```
Living Room:
  ├── Ceiling Light 1
  ├── Ceiling Light 2  
  ├── Floor Lamp
  └── LED Strip

Kitchen:
  ├── Under Cabinet Lights
  ├── Pendant Lights
  └── Ceiling Spots

Bedroom:
  ├── Bedside Lamp 1
  ├── Bedside Lamp 2
  └── Main Light
```

#### 1.2 Create Zones in Hue App

Group related rooms into zones for broader control:

```
Ground Floor Zone:
  ├── Living Room
  ├── Kitchen  
  └── Dining Room

Upper Floor Zone:
  ├── Bedroom
  ├── Bathroom
  └── Office
```

### Step 2: Generate Calaos IO Configuration

Once your Hue devices are organized, generate the Calaos IO configuration.

#### 2.1 Run HUE2MQTT Discovery

Connect to your Calaos server via SSH and run the discovery command using podman:

```bash
ssh root@your-calaos-server.local

# Generate Calaos IO configuration using podman
podman run --rm \
  -v /mnt/calaos/hue2mqtt/:/config \
  docker.io/kwame42/hue2mqtt \
  mix discovery.calaos \
    --toml-config /config/config.toml \
    --io-output-file /config/hue-output.xml \
    --hue-zones-and-rooms /config/hue_rooms_and_zones.json \
    --hue-lights /config/hue_lights.json \
    --id-start 1000
```

**Parameters explained:**
- `-v /mnt/calaos/hue2mqtt/:/config`: Mount configuration directory into container
- `--toml-config /config/config.toml`: Path to your HUE2MQTT configuration file (inside container)
- `--io-output-file /config/hue-output.xml`: Where to save the generated Calaos XML configuration (inside container, will be at `/mnt/calaos/hue2mqtt/hue-output.xml` on host)
- `--hue-zones-and-rooms /config/hue_rooms_and_zones.json`: **Reference file** - JSON dump of your Hue bridge's room and zone structure for informational purposes. This helps you identify room/zone names and their associated IDs when reviewing the generated configuration.
- `--hue-lights /config/hue_lights.json`: **Reference file** - JSON dump of all your Hue lights and grouped lights with their IDs. Use this to identify specific light IDs and understand which lights are grouped together. These IDs will appear in the topics within `hue-output.xml`.
- `--id-start 1000`: Starting ID number for Calaos devices (avoid conflicts with existing IOs)

**Generated files:**
- `/mnt/calaos/hue2mqtt/hue-output.xml` - The main Calaos IO configuration file to integrate into your system
- `/mnt/calaos/hue2mqtt/hue_rooms_and_zones.json` - Reference information about your Hue rooms and zones
- `/mnt/calaos/hue2mqtt/hue_lights.json` - Reference information about all your Hue lights and their IDs

**Note**: The JSON files are for reference only to help you understand your Hue setup. The actual Calaos configuration is in the XML file.

#### 2.2 Understanding the Reference Files

After running the discovery command, you'll have three files:

**hue-output.xml** - This is the main file containing the Calaos configuration to integrate. Each light will have IDs in the format:
```xml
topic_pub="hue2mqtt/light/11111111-1111-1111-1111-111111111111/set"
topic_sub="hue2mqtt/grouped_light/42424242-4242-4242-4242-424242424242"
```
These UUIDs correspond to the `id` fields in the JSON reference files.

**hue_rooms_and_zones.json** - Contains your Hue room and zone structure with the actual Hue bridge API v2 format:
```json
{
  "room": {
    "data": [
      {
        "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "metadata": {
          "name": "Kitchen"
        },
        "type": "room"
      }
    ]
  },
  "zone": {
    "data": [
      {
        "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        "metadata": {
          "name": "Ground Floor"
        },
        "type": "zone"
      }
    ]
  }
}
```

**hue_lights.json** - Contains all your lights and grouped lights directly from the Hue bridge API v2:
```json
{
  "light": {
    "data": [
      {
        "id": "11111111-1111-1111-1111-111111111111",
        "metadata": {
          "name": "Kitchen Ceiling 1"
        },
        "on": {
          "on": true
        },
        "dimming": {
          "brightness": 100.0
        },
        "type": "light"
      }
    ]
  },
  "grouped_light": {
    "data": [
      {
        "id": "42424242-4242-4242-4242-424242424242",
        "id_v1": "/groups/101",
        "owner": {
          "rid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "rtype": "room"
        },
        "on": {
          "on": false
        },
        "dimming": {
          "brightness": 0.0
        },
        "type": "grouped_light"
      }
    ]
  }
}
```

**Key information in the JSON files:**
- `id`: The unique identifier used in MQTT topics (e.g., `42424242-4242-4242-4242-424242424242`)
- `metadata.name`: Human-readable name of the device/room/zone
- `owner.rid`: For grouped_lights, this links to the room or zone ID (e.g., `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa` links to "Kitchen" room)
- `owner.rtype`: Indicates if it's a "room" or "zone"

**Using the reference files:** When you see an ID like `42424242-4242-4242-4242-424242424242` in the XML configuration's MQTT topic, you can search for it in the JSON files to understand which room, zone, or light group it represents. Look for the `owner.rid` in grouped_lights to find which room owns that group.

### Step 3: Configure Calaos Server

Now integrate the generated Hue device IOs into your Calaos configuration.

#### 3.1 Backup Existing Configuration

Before making any changes, always backup your current Calaos configuration:

```bash
ssh root@your-calaos-server.local

# Create backup with timestamp
cp /mnt/calaos/config/io.xml /mnt/calaos/config/io.xml.backup.$(date +%Y%m%d_%H%M%S)
cp /mnt/calaos/config/rules.xml /mnt/calaos/config/rules.xml.backup.$(date +%Y%m%d_%H%M%S)
```

#### 3.2 Integrate Generated IOs into Calaos Configuration

The generated file `/mnt/calaos/hue2mqtt/hue-output.xml` contains all your Hue devices as Calaos IOs. You need to copy the IO definitions and paste them into your main Calaos IO file.

Edit your main Calaos IO file `/mnt/calaos/config/io.xml` and paste the copied content (from `/mnt/calaos/hue2mqtt/hue-output.xml`) inside your existing `<calaos:io>` section, typically organized by rooms.

**Important notes:**

1. For each light, you can find between 1 and 3 different Calaos IOs:
   - The first one is always for turning the light on or off
   - The second one manages the dimmer
   - An optional third one changes the color

2. There are grouped lights that can represent several lights from a room or a zone. To check the names:
   - For room/zone names: check `/mnt/calaos/hue2mqtt/hue_rooms_and_zones.json`
   - For individual light or grouped_light names: check `/mnt/calaos/hue2mqtt/hue_lights.json`

Here's an example of the configuration to manage all 5 lights in the kitchen that are grouped (room or zone) in your Hue app:

```xml
<calaos:output data='{&quot;on&quot;: {&quot;on&quot;: __##VALUE##__}}' enabled="true" gui_type="light" id="output_6" io_type="output" log_history="true" logged="true" name="Kitchen (on/off)" off_value="false" on_value="true" path="on/on" topic_pub="hue2mqtt/grouped_light/42424242-4242-4242-4242-424242424242/set" topic_sub="hue2mqtt/grouped_light/42424242-4242-4242-4242-424242424242" type="MqttOutputLight" visible="true" />
<calaos:output data='{&quot;dimming&quot;: {&quot;brightness&quot;: __##VALUE##__}}' enabled="true" gui_type="light_dimmer" id="output_654" io_type="output" log_history="true" logged="true" name="Kitchen (dimmed)" path="dimming/brightness" topic_pub="hue2mqtt/grouped_light/42424242-4242-4242-4242-424242424242/set" topic_sub="hue2mqtt/grouped_light/42424242-4242-4242-4242-424242424242" type="MqttOutputLightDimmer" visible="true" />
<calaos:output data='{&quot;color&quot;:{&quot;xy&quot;:{&quot;x&quot;:__##VALUE_X##__,&quot;y&quot;:__##VALUE_Y##__}}}' enabled="true" gui_type="light_rgb" id="output_655" io_type="output" log_history="true" logged="true" name="Kitchen (color)" path_x="color/xy/x" path_y="color/xy/y" topic_pub="hue2mqtt/grouped_light/42424242-4242-4242-4242-424242424242/set" topic_sub="hue2mqtt/grouped_light/42424242-4242-4242-4242-424242424242" type="MqttOutputLightRGB" visible="true" />
```

**Note:** The ID `42424242-4242-4242-4242-424242424242` is the grouped_light ID from your Hue bridge. You can find this in `hue_lights.json` under `grouped_light.data[].id`. The `owner.rid` field (e.g., `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa`) will tell you which room (e.g., "Kitchen") this group belongs to.

If you want to manage each individual light as well, add:

```xml
<calaos:output data='{&quot;on&quot;: {&quot;on&quot;: __##VALUE##__}}' enabled="true" gui_type="light" id="output_7" io_type="output" log_history="true" logged="true" name="Kitchen Light 1 (on/off)" off_value="false" on_value="true" path="on/on" topic_pub="hue2mqtt/light/11111111-1111-1111-1111-111111111111/set" topic_sub="hue2mqtt/light/11111111-1111-1111-1111-111111111111" type="MqttOutputLight" visible="true" />
<calaos:output data='{&quot;dimming&quot;: {&quot;brightness&quot;: __##VALUE##__}}' enabled="true" gui_type="light_dimmer" id="output_656" io_type="output" log_history="true" logged="true" name="Kitchen Light 1 (dimmed)" path="dimming/brightness" topic_pub="hue2mqtt/light/11111111-1111-1111-1111-111111111111/set" topic_sub="hue2mqtt/light/11111111-1111-1111-1111-111111111111" type="MqttOutputLightDimmer" visible="true" />
<calaos:output data='{&quot;color&quot;:{&quot;xy&quot;:{&quot;x&quot;:__##VALUE_X##__,&quot;y&quot;:__##VALUE_Y##__}}}' enabled="true" gui_type="light_rgb" id="output_657" io_type="output" log_history="true" logged="true" name="Kitchen Light 1 (color)" path_x="color/xy/x" path_y="color/xy/y" topic_pub="hue2mqtt/light/11111111-1111-1111-1111-111111111111/set" topic_sub="hue2mqtt/light/11111111-1111-1111-1111-111111111111" type="MqttOutputLightRGB" visible="true" />

<calaos:output data='{&quot;on&quot;: {&quot;on&quot;: __##VALUE##__}}' enabled="true" gui_type="light" id="output_8" io_type="output" log_history="true" logged="true" name="Kitchen Light 2 (on/off)" off_value="false" on_value="true" path="on/on" topic_pub="hue2mqtt/light/22222222-2222-2222-2222-222222222222/set" topic_sub="hue2mqtt/light/22222222-2222-2222-2222-222222222222" type="MqttOutputLight" visible="true" />
<calaos:output data='{&quot;dimming&quot;: {&quot;brightness&quot;: __##VALUE##__}}' enabled="true" gui_type="light_dimmer" id="output_658" io_type="output" log_history="true" logged="true" name="Kitchen Light 2 (dimmed)" path="dimming/brightness" topic_pub="hue2mqtt/light/22222222-2222-2222-2222-222222222222/set" topic_sub="hue2mqtt/light/22222222-2222-2222-2222-222222222222" type="MqttOutputLightDimmer" visible="true" />

...

```
#### 3.3 Restart Calaos Server

Apply the new configuration by restarting Calaos:

```bash
# Restart Calaos server
systemctl restart calaos-server

# Check status - should show "active (running)"
systemctl status calaos-server

# Monitor logs for any errors
journalctl -u calaos-server -f
```

### Step 4: Troubleshooting

#### 4.1 Configuration Errors

If Calaos fails to start after configuration changes:

1. Stop Calaos: `systemctl stop calaos-server`
2. Restore backup: `cp /mnt/calaos/config/io.xml.backup.YYYYMMDD_HHMMSS /mnt/calaos/config/io.xml`
3. Fix the XML errors
4. Try again

#### 4.2 Test from Calaos Interface

- Open Calaos Home interface
- Navigate to your rooms
- Test turning lights on/off
- Verify dimming functionality
- Test color changes for RGB lights
- Check motion sensor triggers

---
