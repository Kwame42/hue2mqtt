# Contributing to HUE2MQTT

First off, thank you for considering contributing to HUE2MQTT! 🎉

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps which reproduce the problem**
- **Provide specific examples to demonstrate the steps**
- **Describe the behavior you observed after following the steps**
- **Explain which behavior you expected to see instead and why**
- **Include configuration files, logs, and environment details**

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- **Use a clear and descriptive title**
- **Provide a step-by-step description of the suggested enhancement**
- **Provide specific examples to demonstrate the steps**
- **Describe the current behavior and the behavior you expected to see**
- **Explain why this enhancement would be useful**

### Pull Requests

1. Fork the repository
2. Create a new branch: `git checkout -b feature/your-feature-name`
3. Make your changes
4. Add tests for your changes
5. Run the test suite: `mix test`
6. Run the linter: `mix credo`
7. Run the formatter: `mix format`
8. Commit your changes: `git commit -am 'Add some feature'`
9. Push to the branch: `git push origin feature/your-feature-name`
10. Submit a pull request

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Kwame42/hue2mqtt.git
   cd hue2mqtt
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Run tests:
   ```bash
   mix test
   ```

4. Start the application:
   ```bash
   mix hue.mqtt.server --help
   ```

## Style Guide

### Elixir Style Guide

We follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide) and use `mix format` to ensure consistent formatting.

### Documentation

- All public functions must have `@doc` annotations
- All public functions must have `@spec` type specifications
- All modules must have `@moduledoc` annotations
- Include examples in documentation where helpful
- Keep documentation up-to-date with code changes

### Testing

- Write tests for all new functionality
- Maintain or improve test coverage
- Use descriptive test names
- Test both success and error cases

### Commit Messages

- Use the present tense ("Add feature" not "Added feature")
- Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests liberally after the first line

## Architecture

HUE2MQTT follows OTP principles with a supervision tree:

```
HueMqtt.Application
├── Mqtt (MQTT client)
├── Hue.Api (HTTP client)
├── Hue.Conf (Configuration)
└── Hue.Stream (Event streaming)
```

### Key Modules

- **Mqtt**: Handles MQTT broker communication and topic parsing
- **Hue.Api**: HTTP client with rate limiting for Hue bridge communication
- **Hue.Conf**: Configuration management and bridge discovery
- **Hue.Stream**: Real-time event streaming from Hue bridges

## Release Process

1. Update version in `mix.exs`
2. Update `CHANGELOG.md`
3. Create a git tag: `git tag v0.1.0`
4. Push tag: `git push origin v0.1.0`
5. GitHub Actions will automatically publish to Hex.pm and Docker Hub

## Questions?

Don't hesitate to ask questions by creating an issue or starting a discussion on GitHub!
