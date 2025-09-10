# HUE2MQTT

[![Hex.pm](https://img.shields.io/hexpm/v/hue_mqtt.svg)](https://hex.pm/packages/hue_mqtt)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/hue_mqtt)
[![Docker](https://img.shields.io/docker/pulls/kwame42/hue2mqtt.svg)](https://hub.docker.com/r/kwame42/hue2mqtt)
[![License: BSD-2-Clause](https://img.shields.io/badge/License-BSD_2--Clause-orange.svg)](https://opensource.org/licenses/BSD-2-Clause)
[![GitHub stars](https://img.shields.io/github/stars/Kwame42/hue2mqtt.svg)](https://github.com/Kwame42/hue2mqtt/stargazers)

V0.1b - Beta test mode

## Overview
HUE2MQTT is a proxy application that bridges communication between a Philips Hue bridge and MQTT message queues. It enables bidirectional data transfer, allowing you to:
- Forward messages from your Hue bridge to MQTT topics
- Send commands from MQTT to your Hue bridge

## Installation

### From Hex.pm

Add `hue_mqtt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hue_mqtt, "~> 0.1.0"}
  ]
end
```

Then run:
```bash
mix deps.get
```

### From Source

```bash
git clone https://github.com/Kwame42/hue2mqtt.git
cd hue2mqtt
mix deps.get
mix compile
```

## Configuration

### Connection Settings

**MQTT Configuration (using Tortoise client):**
```toml
[mqtt]
host = "10.0.0.1"
port = 1883
client_id = "hue2mqtt"
username = ""
password = ""
keep_alive = 60
```

**Hue Bridge Configuration:**
```toml
[hue]
ip = "10.0.0.2"
username = "<from the hue configuration>"
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

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the BSD 2-Clause License - see the [LICENSE](LICENSE) file for details.

## Support

- 📚 [Documentation](https://hexdocs.pm/hue_mqtt)
- 🐛 [Issue Tracker](https://github.com/Kwame42/hue2mqtt/issues)
- 💬 [Discussions](https://github.com/Kwame42/hue2mqtt/discussions)
- 🐳 [Docker Hub](https://hub.docker.com/r/kwame42/hue2mqtt)

## Links

- [Philips Hue API Documentation](https://developers.meethue.com/develop/hue-api-v2/)
- [MQTT Protocol](https://mqtt.org/)
- [Calaos Home Automation](https://calaos.fr/)
- [Elixir Language](https://elixir-lang.org/)

## Acknowledgments

- Thanks to the Philips Hue team for their excellent API
- Thanks to the EMQX team for the MQTT client library
- Thanks to the Elixir community for the amazing ecosystem

