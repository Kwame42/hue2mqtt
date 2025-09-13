defmodule Hue.Stream do
  @moduledoc """
  Module to connect to HUE EventStream using Req for real-time event streaming.
  
  This GenServer manages persistent streaming connections to multiple Hue bridges,
  receiving real-time device events and forwarding them to MQTT.
  
  Uses Req with Task-based streaming instead of HTTPoison async messages for
  better performance and cleaner SSL handling.
  """
  
  use GenServer
  use Log
  require Logger

  defstruct [:connections, :tasks]

  @doc """
  Starts the Hue Stream GenServer that manages EventStream connections to Hue bridges.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_default),
    do: GenServer.start_link(__MODULE__, %{}, name: Hue.Stream)

  @doc """
  Initializes the Stream GenServer by establishing streaming connections 
  to all configured Hue bridges for real-time event streaming.
  
  ## Returns
  
  {:ok, state} where state contains connections and task references
  """
  @spec init(any()) :: {:ok, %__MODULE__{}}
  def init(_default) do
    info("Initializing Hue Stream connections")
    
    connections = 
      Hue.Conf.get_conf()
      |> Map.get(:bridges_list)
      |> Enum.reduce(%{}, fn {_, bridge}, acc ->
        case start_streaming_connection(bridge) do
          {:ok, task_pid} -> 
            task_ref = Process.monitor(task_pid)
            Map.put(acc, task_ref, %{bridge: bridge, task_pid: task_pid, status: :connecting})
          {:error, reason} ->
            error("Failed to start connection to bridge #{bridge.ip}: #{inspect(reason)}")
            acc
        end
      end)
    
    info("Started #{map_size(connections)} bridge connections")
    {:ok, %__MODULE__{connections: connections, tasks: %{}}}
  end

  # Handle streaming task messages
  def handle_info({:stream_chunk, task_ref, chunk}, state) do
    case Map.get(state.connections, task_ref) do
      %{bridge: bridge} = conn_info ->
	IO.inspect(chunk, label: "Received chunk from bridge #{bridge.ip}")
        process_event_chunk(chunk, bridge)
        new_connections = Map.put(state.connections, task_ref, %{conn_info | status: :connected})
        {:noreply, %{state | connections: new_connections}}
      nil ->
        warning("Received chunk from unknown task: #{inspect(task_ref)}")
        {:noreply, state}
    end
  end

  def handle_info({:stream_error, task_ref, error}, state) do
    case Map.get(state.connections, task_ref) do
      %{bridge: bridge} ->
        error("Stream error for bridge #{bridge.ip}: #{inspect(error)}")
        # Remove the failed connection and restart it
        new_connections = Map.delete(state.connections, task_ref)
        
        # Restart connection after a delay
        Process.send_after(self(), {:restart_connection, bridge}, 5_000)
        
        {:noreply, %{state | connections: new_connections}}
      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:restart_connection, bridge}, state) do
    info("Restarting connection to bridge #{bridge.ip}")
    
    case start_streaming_connection(bridge) do
      {:ok, task_pid} ->
        task_ref = Process.monitor(task_pid)
        new_connections = Map.put(state.connections, task_ref, %{
          bridge: bridge, 
          task_pid: task_pid, 
          status: :reconnecting
        })
        {:noreply, %{state | connections: new_connections}}
      {:error, reason} ->
        error("Failed to restart connection to bridge #{bridge.ip}: #{inspect(reason)}")
        # Try again later
        Process.send_after(self(), {:restart_connection, bridge}, 10_000)
        {:noreply, state}
    end
  end

  # Handle task termination
  def handle_info({:DOWN, task_ref, :process, _pid, reason}, state) do
    case Map.get(state.connections, task_ref) do
      %{bridge: bridge} ->
        warning("Streaming task terminated for bridge #{bridge.ip}: #{inspect(reason)}")
        new_connections = Map.delete(state.connections, task_ref)
        
        # Only restart if it wasn't a normal shutdown
        if reason != :normal do
          Process.send_after(self(), {:restart_connection, bridge}, 5_000)
        end
        
        {:noreply, %{state | connections: new_connections}}
      nil ->
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    warning("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Start a streaming connection using Req with a Task
  defp start_streaming_connection(bridge) do
    parent_pid = self()
    
    task_pid = Task.start_link(fn ->
      stream_events(bridge, parent_pid)
    end)
    
    case task_pid do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end

  # The actual streaming function that runs in a Task
  defp stream_events(bridge, parent_pid) do
    url = Hue.Conf.Bridge.url(bridge, "/eventstream/clip/v2")
    headers = Hue.Conf.Bridge.headers(bridge)
    
    info("Starting event stream connection to #{url}")
    
    task_ref = make_ref()
    
    try do
      Req.get!(url,
        headers: headers,
        connect_options: [
          transport_opts: [
            verify: :verify_none,
            versions: [:"tlsv1.2", :"tlsv1.3"]
          ]
        ],
        receive_timeout: :infinity,
        into: fn
          {:data, data}, {req, resp, acc} ->
            # Send chunk to parent GenServer
            send(parent_pid, {:stream_chunk, task_ref, data})
            {:cont, {req, resp, acc}}
          
          {:error, reason}, {req, resp, acc} ->
            send(parent_pid, {:stream_error, task_ref, reason})
            {:halt, {req, resp, acc}}
        end
      )
    rescue
      exception ->
        error("Exception in event stream for bridge #{bridge.ip}: #{inspect(exception)}")
        send(parent_pid, {:stream_error, task_ref, exception})
    end
  end

  # Process incoming event chunks
  defp process_event_chunk(chunk, bridge) do
    try do
      # Hue EventStream can send multiple JSON objects separated by newlines
      chunk
      |> String.split("\n")
      |> Enum.reject(&(&1 == "" || String.trim(&1) == ""))
      |> Enum.each(fn json_line ->
        case Jason.decode(json_line) do
          {:ok, events} when is_list(events) ->
            process_events(events)
          {:ok, event} when is_map(event) ->
            process_events([event])
          {:error, reason} ->
            warning("Failed to decode JSON from bridge #{bridge.ip}: #{inspect(reason)}")
            warning("Problematic JSON: #{inspect(json_line)}")
        end
      end)
    rescue
      exception ->
        error("Exception processing chunk from bridge #{bridge.ip}: #{inspect(exception)}")
        error("Chunk content: #{inspect(chunk)}")
    end
  end

  # Process individual events and forward to MQTT
  defp process_events(events) when is_list(events) do
    Enum.each(events, fn event ->
      case event do
        %{"data" => data} when is_list(data) ->
          Enum.each(data, fn %{"type" => type, "id" => id} = payload ->
            Mqtt.publish_to_mqtt("#{type}/#{id}", payload)
          end)
        
        %{"type" => type, "id" => id} = payload ->
          # Single event format
          Mqtt.publish_to_mqtt("#{type}/#{id}", payload)
          
        _ ->
          info("Unrecognized event format: #{inspect(event)}")
      end
    end)
  end

  @doc """
  Returns the current status of all bridge connections.
  """
  @spec get_connection_status() :: %{reference() => map()}
  def get_connection_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def handle_call(:get_status, _from, state) do
    status = 
      state.connections
      |> Enum.map(fn {_ref, %{bridge: bridge, status: status}} ->
        {bridge.ip, %{status: status, bridge_id: bridge.id}}
      end)
      |> Enum.into(%{})
    
    {:reply, status, state}
  end

  @doc """
  Converts a reference to a string representation for use as map keys.
  
  ## Parameters
  
  - `ref` - Reference to convert
  
  ## Returns
  
  String representation of the reference.
  """
  @spec ref_to_string(reference()) :: String.t()
  def ref_to_string(ref),
    do: inspect(ref)
end
