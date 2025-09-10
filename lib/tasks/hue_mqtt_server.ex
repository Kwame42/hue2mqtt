defmodule Mix.Tasks.Hue.Mqtt.Server do
  @moduledoc """
  Mix task for starting the HUE2MQTT server.
  
  This task loads configuration from command-line arguments and starts the
  HUE2MQTT application server. It handles both interactive (IEx) and 
  non-interactive execution modes.
  
  ## Usage
  
      mix hue.mqtt.server [options]
  
  See `mix hue.mqtt.server --help` for available options.
  """
  
  use Mix.Task
  alias Hue.Conf
  
  @doc """
  Runs the HUE2MQTT server task.
  
  ## Parameters
  
  - `args` - Command-line arguments for configuration
  """
  @spec run([String.t()]) :: :ok
  @impl Mix.Task
  def run(args) do
    Conf.application_load_config_in_env(args)
    Mix.Tasks.Run.run(run_args())
  end

  @spec iex_running?() :: boolean()
  defp iex_running?,
    do: Code.ensure_loaded?(IEx) and IEx.started?()

  @spec run_args() :: [String.t()]
  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end
end
