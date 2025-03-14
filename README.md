# HUE2MQTT Help

V0.1b - Beta test mode

## Overview
HUE2MQTT is a proxy application that bridges communication between a Philips Hue bridge and MQTT message queues. It enables bidirectional data transfer, allowing you to:
- Forward messages from your Hue bridge to MQTT topics
- Send commands from MQTT to your Hue bridge

## Configuration

### Connection Settings
```
[mqtt]
host = "10.0.0.1"
port = 1883
enable_tls = false
force_protocol_version_3_1 = true
enable_auth = false
username = ""
password = ""
topic_prefix = "hue2mqtt"

[hue]
ip = "10.0.0.2"
username = "<from the hue configuraton>"
id = "124af34gh34df784e"
```

### Docker installation

`docker pull kwame42/hue2mqtt:latest`

Default running command: mix hue.mqtt.server

try to load HUE_MQTT_CONFIG_FILE environment variable to read confgi file from. You can mount `/data` and load configuraiton there. You can also specify the io.XML output file in the same directory (see help section)

### Topic Structure
- **From Hue to MQTT**: `hue2mqtt/[device_type]/[device_id]/`
- **From MQTT to Hue**: `hue2mqtt/[device_type]/[device_id]/set`

## Usage Examples

### Receiving Hue Updates
When a light changes state on the Hue bridge, HUE2MQTT publishes to:
```
hue2mqtt/light/YTnC8Devnh4BSSR8J → {"on":true,"bri":254,"hue":8418,"sat":140}
```

### Controlling Hue Devices
To turn on a light, publish to:
```
hue2mqtt/light/YTnC8Devnh4BSSR8J/set → {"on": {"on": true}}
```

## Supported resources 
light, scene, room, zone, bridge_home, grouped_light, device, bridge, device_software_update, device_power, zigbee_connectivity, zgp_connectivity, zigbee_device_discovery, motion, service_group, grouped_motion, grouped_light_level, camera_motion, temperature, light_level, button, relative_rotary, behavior_script, behavior_instance, geofence_client, geolocation, entertainment_configuration, entertainment, homekit, matter, matter_fabric, smart_scene, contact, tamper

## Calaos support

You can create an io.xml file for Calaos using `mix discovery.calaos [options]` with light, grouped_light, zone, and room from the bridge.

## Troubleshooting
- Verify HUE connection settings
- Verify MQTT broker connection settings

## Command Line Options
```
Usage: mix hue.mqtt.server [global options]
       mix discovery.calaos [global options] [calaos options]

Global options:
 --hue-config: Hue Config file path
 --mqtt_config: MQTT Config file path, can be set as a environment variable HUE_MQTT_CONFIG_FILE (see docker section)
 --toml_config: TOML config file with hue and mqtt configuration
 --help: help message

Calaos options:
 --io-output-file: Calaos IO output filename 
 --id-start: Calaos IO id starting number - default is 0
```

