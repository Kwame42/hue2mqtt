defmodule HueMqtt.MixProject do
  use Mix.Project

  def project do
    [
      app: :hue_mqtt,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {HueMqtt.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:emqtt, github: "emqx/emqtt", tag: "master", system_env: [{"BUILD_WITHOUT_QUIC", "1"}]},
      {:httpoison, "~> 2.2.1"},
      {:pubsub, "~> 1.0"},
      {:toml, "~> 0.7.0"},
      # {:mdns_lite, "0.8.11"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
