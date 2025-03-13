defmodule Mix.Tasks.Hue.Mqtt.Server do
  @moduledoc "Hue discovery qnd configuration"
  use Mix.Task
  alias Hue.Conf
  
  @impl Mix.Task
  def run(args) do
    Conf.application_load_config_in_env(args)
    Mix.Tasks.Run.run(run_args())
  end

  defp iex_running?,
    do: Code.ensure_loaded?(IEx) and IEx.started?()

  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end
end
