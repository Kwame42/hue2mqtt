# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive documentation for all modules and functions
- Type specifications (@spec) for all public functions
- Docker support with published image on Docker Hub
- Calaos home automation integration
- MIT License and proper package metadata for Hex.pm publishing

### Changed
- **BREAKING**: Replaced emqtt (GitHub dependency) with Tortoise MQTT client from Hex.pm
- Improved error handling and retry logic
- Enhanced MQTT topic parsing
- Better configuration validation
- MQTT configuration format updated for Tortoise compatibility

### Fixed
- Rate limiting for Hue bridge API requests
- SSL certificate handling for local bridges
- Package dependencies now compatible with Hex.pm publishing requirements

## [0.1.0] - 2024-08-31

### Added
- Initial release of HUE2MQTT
- Bidirectional communication between Philips Hue and MQTT
- Support for all Hue API v2 resources
- Real-time event streaming from Hue bridges
- Multi-bridge support
- TOML, JSON, and auto-discovery configuration options
- Rate limiting and retry mechanisms
- Docker containerization
- Mix tasks for server startup and Calaos discovery

### Features
- **Resource Support**: lights, scenes, rooms, zones, sensors, and more
- **Configuration**: TOML files, JSON files, auto-discovery
- **MQTT Topics**: `hue2mqtt/[device_type]/[device_id]/[method]`
- **Rate Limiting**: Automatic throttling to respect Hue API limits
- **Event Streaming**: Real-time updates via Hue EventStream
- **Error Handling**: Comprehensive retry logic and error reporting

### Technical Details
- Elixir/OTP application with GenServer architecture
- Supervision tree for fault tolerance
- HTTP client with connection pooling
- MQTT client with keep-alive connections
- SSL support with certificate bypass for local bridges

[Unreleased]: https://github.com/Kwame42/hue2mqtt/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kwame42/hue2mqtt/releases/tag/v0.1.0
