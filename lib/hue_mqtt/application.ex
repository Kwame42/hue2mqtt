defmodule HueMqtt.Application do
  @moduledoc """
  Main OTP Application for HUE2MQTT.
  
  This application starts and supervises all core processes required for
  bridging communication between Philips Hue bridges and MQTT brokers:
  
  - MQTT client connection and message handling
  - Hue API client for bridge communication  
  - Configuration management for bridges and settings
  - Event streaming from Hue bridges for real-time updates
  
  The supervisor uses a :one_for_one strategy, restarting failed processes
  individually while maintaining the overall system stability.
  
  ## Supervision Tree
  
  1. `Mqtt` - MQTT broker connection and message routing
  2. `Hue.Api` - HTTP API client for Hue bridge communication  
  3. `Hue.Conf` - Configuration management (must start after Hue.Api)
  4. `Hue.Stream` - Real-time event streaming (must start after Hue.Conf)
  """
  
  use Application

  @doc """
  Starts the HUE2MQTT application and its supervision tree.
  
  ## Parameters
  
  - `_type` - Application start type (ignored)
  - `_args` - Application start arguments (ignored)
  
  ## Returns
  
  {:ok, pid} on successful start, {:error, reason} on failure.
  """
  @spec start(any(), any()) :: {:ok, pid()} | {:error, any()}
  @impl true
  def start(_type, _args) do
    children = [
#      PubSub,
      #Mqtt,
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
