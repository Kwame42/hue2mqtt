defmodule HueMqtt.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Kwame42/hue2mqtt"
  @homepage_url "https://github.com/Kwame42/hue2mqtt"

  def project do
    [
      app: :hue_mqtt,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      
      # Hex package information
      description: description(),
      package: package(),
      
      # Documentation
      name: "HUE2MQTT",
      source_url: @source_url,
      homepage_url: @homepage_url,
      docs: docs(),
      
      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      
      # Dialyzer for static analysis
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :race_conditions, :underspecs]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl, :crypto],
      mod: {HueMqtt.Application, []}
    ]
  end

  defp description do
    """
    HUE2MQTT is a proxy application that bridges communication between Philips Hue bridges 
    and MQTT message queues. It enables bidirectional data transfer, real-time event streaming,
    and supports multiple bridge configurations with rate limiting and retry logic.
    """
  end

  defp package do
    [
      name: "hue_mqtt",
      maintainers: ["Kwame"],
      licenses: ["BSD-2-Clause"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/hue_mqtt",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Issues" => "#{@source_url}/issues",
        "Docker Hub" => "https://hub.docker.com/r/kwame42/hue2mqtt",
	"HUE api documentation" => "https://developers.meethue.com/develop/hue-api/",
	"MQTT protocol" => "https://mqtt.org/",
	"Calaos" => "https://www.calaos.fr/"
      },
      files: [
        "lib",
        "config", 
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ],
      exclude_patterns: [
        ".git*",
        "test/",
        "_build/",
        "deps/",
        "doc/",
        "priv/plts/"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "HUE2MQTT",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @homepage_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "Core": [
          HueMqtt.Application,
          Mqtt,
          Log
        ],
        "Hue API": [
          Hue,
          Hue.Api,
          Hue.Api.Resource,
          Hue.Api.Response,
          Hue.Api.Response.Timestamp
        ],
        "Configuration": [
          Hue.Conf,
          Hue.Conf.Bridge
        ],
        "Streaming": [
          Hue.Stream
        ],
        "Mix Tasks": [
          Mix.Tasks.Hue.Mqtt.Server,
          Mix.Tasks.Discovery.Calaos
        ]
      ],
      groups_for_functions: [
        "HTTP API": &(&1[:section] == :http_api),
        "Configuration": &(&1[:section] == :configuration),
        "MQTT": &(&1[:section] == :mqtt)
      ]
    ]
  end

  defp deps do
    [
      # Production dependencies
      {:jason, "~> 1.4"},
      {:tortoise, "~> 0.10"},  # Pure Elixir MQTT client from Hex.pm
      {:httpoison, "~> 2.2"},
      {:pubsub, "~> 1.0"},
      {:toml, "~> 0.7"},
      
      # Development and test dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
