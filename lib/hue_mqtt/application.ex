defmodule HueMqtt.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
#      PubSub,
#      Mqtt,
      # Starts a worker by calling: HueMqtt.Worker.start_link(arg)
      # {HueMqtt.Worker, arg}
      ## WATCHOUT for dependensies betwee Hue.Api and Hue.Conf (
      Hue.Api,    # 1. Must be, before Hue.conf
      Hue.Conf,   # 2.
      Hue.Stream, # 3. 
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HueMqtt.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
