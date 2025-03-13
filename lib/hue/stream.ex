defmodule Hue.Stream do
  @moduledoc """
  Module to connect to HUE Stream. must be call passing the bridge as a parameter
  """
  
  use GenServer
  use Log
  require Logger

  def start_link(_default),
    do: GenServer.start_link(__MODULE__, %{}, name: Hue.Stream)

  @doc """
  
  """
  def init(_default) do
    connexions =
      Hue.Conf.get_conf
      |> Map.get(:bridges_list)
      |> Enum.reduce(%{}, fn {_, bridge}, acc ->
        case async_connection(bridge) do
	  %HTTPoison.AsyncResponse{id: ref} ->
	    Map.put(acc, ref_to_string(ref), bridge)
	  _ -> acc |> info()
	end
      end)
      info(connexions)
    {:ok, connexions}
  end

  def handle_info(%HTTPoison.AsyncChunk{id: _ref, chunk: updates_list}, connections) do
    updates_list
    |> Jason.decode!()
    |> Enum.map(fn update ->
      update
      |> Map.get("data")
      |> Enum.map(fn %{"type" => type, "id" => id} = payload ->
	Mqtt.publish_to_mqtt("#{type}/#{id}", payload)
      end)
    end)
    {:noreply, connections}
  end
  
  def handle_info(%HTTPoison.AsyncEnd{id: old_ref}, connections) do
    new_connections =
      with {:ok, bridge} <- Map.fetch(connections, ref_to_string(old_ref)),
	   %HTTPoison.AsyncResponse{id: new_ref} <- async_connection(bridge) do
	connections
	|> Map.delete(ref_to_string(old_ref))
	|> Map.put(ref_to_string(new_ref), bridge)
      else
	_ -> connections
      end

    {:noreply, new_connections}
  end
  
  def handle_info(%HTTPoison.AsyncStatus{id: ref, code: 200}, connections) do
    new_connections =
      with {:ok, _bridge} <- Map.fetch(connections, ref_to_string(ref)) do
	Map.update!(connections, ref_to_string(ref), fn bridge -> Map.put(bridge, :status, 200) end)
      else
	_ -> connections
      end
    info(new_connections)
    {:noreply, new_connections}
  end

  def handle_info(%HTTPoison.AsyncStatus{id: ref, code: error}, connections) do
    with {:ok, bridge} <- Map.fetch(connections, ref_to_string(ref)) do
      error("Connection failed to bridge [#{bridge.ip}]: error code #{inspect(error)}")
    end
    {:noreply, connections}
  end

  def handle_info(header, connections) do
    warning("Unknow header #{inspect(header)}")
    {:noreply, connections}
  end

  ##
  ## HTTPpoisons options: 
  ##   - {:ssl, [{:verify, :verify_none}]} : no ssl client verification
  ##   - recv_timeout: :infinity : Timeout inifinite to listen until somehting happen on the bridge
  ##   - stream_to: self() : send async in formation back to ourself
  ##   - hackney: [pool: :default] : keep-alive connection to the bridge until explicit closing from the bridge
  ##
  
  defp async_connection(bridge) do
    info("Connecting to bridge #{Hue.Conf.Bridge.url(bridge)}")
    options = [{:ssl, [{:verify, :verify_none}]}, recv_timeout: :infinity, stream_to: self(), hackney: [pool: :default]]
    # maybe check for already existing connection
    bridge
    |> Hue.Conf.Bridge.url("/eventstream/clip/v2")
    |> HTTPoison.get!(Hue.Conf.Bridge.headers(bridge), options)
  end

  def ref_to_string(ref),
    do: inspect(ref)
end




