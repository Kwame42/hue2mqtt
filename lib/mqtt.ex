defmodule Mqtt do
  @moduledoc """
  MQTT client using Tortoise that manages bidirectional communication between MQTT broker and Hue bridges.
  
  This module handles:
  - MQTT broker connection and subscription management using Tortoise
  - Topic parsing to extract Hue bridge commands
  - Message routing between MQTT and Hue API
  - Configuration loading from various sources (TOML, JSON, environment)
  
  The module subscribes to 'hue2mqtt/#' topics and processes incoming messages,
  forwarding appropriate commands to the Hue bridge via the Hue.Api module.
  
  Uses Tortoise MQTT client which integrates well with OTP supervision trees.
  """

  use Tortoise.Handler
  use Log
  alias Hue.Api.Resource

  defstruct [
    base: "hue2mqtt",
    bridge_id: :default,
    bridge: "",
    resource_id: "",
    module: "",
    method: "get",
    error: [],
    valid?: true
  ]

  @doc """
  Starts the Tortoise MQTT client with this module as the handler.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_) do
    info("MQTT connection setup")
    config = load_config()
    
    Tortoise.Connection.start_link([
      client_id: config[:client_id] || "hue2mqtt",
      handler: {__MODULE__, []},
      server: {Tortoise.Transport.Tcp, [host: config[:host], port: config[:port] || 1883]},
      subscriptions: [{"hue2mqtt/#", 1}],
      user_name: config[:username],
      password: config[:password],
      keep_alive: config[:keep_alive] || 60,
      will: %Tortoise.Package.Publish{
        topic: "hue2mqtt/status",
        payload: "offline",
        qos: 1,
        retain: true
      }
    ])
  end

  # Tortoise.Handler callbacks

  @doc """
  Called when the MQTT connection is established.
  """
  @impl Tortoise.Handler
  def init(args) do
    info("MQTT connection established")
    {:ok, args}
  end

  @doc """
  Called when the connection to the MQTT broker is established.
  """
  @impl Tortoise.Handler
  def connection(status, state) do
    info("MQTT connection status: #{inspect(status)}")
    
    case status do
      :up ->
        # Publish online status when connected
        Tortoise.publish("hue2mqtt", "hue2mqtt/status", "online", qos: 1, retain: true)
      :down ->
        warning("MQTT connection lost")
    end
    
    {:ok, state}
  end

  @doc """
  Called when a message is received on a subscribed topic.
  """
  @impl Tortoise.Handler
  def handle_message(topic, payload, state) do
    info("Received MQTT message on topic: #{topic}")
    
    topic
    |> topic_to_hue()
    |> hue_bridge(payload)
    
    {:ok, state}
  end

  @doc """
  Called when the handler is being terminated.
  """
  @impl Tortoise.Handler
  def terminate(reason, _state) do
    info("MQTT handler terminating: #{inspect(reason)}")
    # Publish offline status when terminating
    Tortoise.publish("hue2mqtt", "hue2mqtt/status", "offline", qos: 1, retain: true)
    :ok
  end

  # Public API

  @doc """
  Publishes a message to the MQTT broker under the hue2mqtt topic prefix.
  
  ## Parameters
  
  - `topic` - The subtopic under hue2mqtt/ to publish to
  - `payload` - The message payload (will be JSON encoded if not a string)
  
  ## Examples
  
      publish_to_mqtt("light/123", %{on: true})
      # Publishes to "hue2mqtt/light/123"
  """
  @spec publish_to_mqtt(String.t(), any()) :: :ok | {:error, any()}
  def publish_to_mqtt(topic, payload) do
    full_topic = "hue2mqtt/#{topic}"
    encoded_payload = if is_binary(payload), do: payload, else: Jason.encode!(payload)
    
    info("Publishing to topic #{full_topic}, payload #{inspect(encoded_payload)}")
    
    Tortoise.publish("hue2mqtt", full_topic, encoded_payload, qos: 0)
  end

  # Private functions (keeping your existing logic)

  defp hue_bridge(%Mqtt{} = hue, _payload) when hue.valid? == false,
    do: error("Mqtt HUE error [#{hue.bridge_id}, #{hue.module}, #{hue.method}]: #{hue.error |> Enum.intersperse("\n") |> List.to_string()}")

  defp hue_bridge(%Mqtt{method: :set} = hue, payload) do
    with {:ok, encoded_payload} <- Jason.decode(payload) do
      info("Set HUE bridge ressource: [#{hue.bridge.ip}/#{hue.module}/#{hue.resource_id}] (#{hue.module}) with payload #{inspect payload}")
      apply(:"Elixir.Hue.Api.#{hue.module}", :put, [hue.bridge, hue.resource_id, encoded_payload])
      |> info()
    else
      _ -> error("Payload: #{inspect(payload)} invalid, must be JSON type")
    end
  end

  defp hue_bridge(%Mqtt{} = hue, _payload) do
    info("MQTT HUE info [#{hue.module}, #{hue.resource_id}]") 
  end
  
  defp hue_bridge(data, _) do
    info("I don't handle this... #{inspect(data)}")
  end

  defp load_config do
    cond do
      not is_nil(Application.get_env(:hue_mqtt, :config_file)) ->
        info("Try to load conf from config map - see toml")
        Application.get_env(:hue_mqtt, :config_file)
	|> Hue.Conf.config_file_to_config_map()
        |> config_map_to_conf()
	  
      not is_nil(Application.get_env(:hue_mqtt, :emqtt)) ->
	info("loading configuration from config.ex")
	Application.get_env(:hue_mqtt, :emqtt)
	
      File.exists?(Application.get_env(:hue_mqtt, :mqtt_config, "")) ->
	info("Try to load conf from file")
	Hue.Conf.read_conf(Application.get_env(:hue_mqtt, :mqtt_config))
        |> mqtt_list_to_config()
        
      true -> raise "no mqtt configuration available, add a config file"
    end
  end

  defp config_map_to_conf(config_map) do
    conf =
      config_map
      |> Map.get("mqtt")
      |> to_keyword()
    
    [port: 1883, client_id: "hue2mqtt", keep_alive: 60]
    |> Keyword.merge(conf)
  end

  defp mqtt_list_to_config(mqtt_config) when is_list(mqtt_config) do
    Enum.into(mqtt_config, %{})
    |> to_keyword()
  end
  
  defp mqtt_list_to_config(mqtt_config), do: mqtt_config
  
  defp to_keyword(map) when is_map(map) do
    Enum.reduce(map, [], fn {key, val}, list ->
      atom_key = if is_atom(key), do: key, else: String.to_atom(key)
      Keyword.put(list, atom_key, val)
    end)
  end

  @methods_list ["get", "set"]
  
  @doc """
  Parses an MQTT topic into a Hue command structure.
  
  ## Topic Format
  
  - `hue2mqtt/resource/resource_id` - GET command
  - `hue2mqtt/resource/resource_id/method` - Specific method (get|set)
  - `hue2mqtt/bridge_id/resource/resource_id` - Multi-bridge support
  - `hue2mqtt/bridge_id/resource/resource_id/method` - Multi-bridge with method
  
  ## Parameters
  
  - `topic` - The MQTT topic string to parse
  
  ## Returns
  
  Returns a %Mqtt{} struct containing parsed bridge, resource, and method information.
  """
  @spec topic_to_hue(String.t()) :: %Mqtt{}
  def topic_to_hue(topic) do
    case String.split(topic, "/") do
      ["hue2mqtt", resource, resource_id] -> cast_to_hue_struct(%{bridge_id: :default, resource: resource, resource_id: resource_id})
      ["hue2mqtt", resource, resource_id, method] when method in @methods_list-> cast_to_hue_struct(%{bridge_id: :default, resource: resource, method: method, resource_id: resource_id})
      ["hue2mqtt", bridge_id, resource, resource_id] -> cast_to_hue_struct(%{bridge_id: bridge_id, resource: resource, resource_id: resource_id})
      ["hue2mqtt", bridge_id, resource, resource_id, method] when method in @methods_list -> cast_to_hue_struct(%{bridge_id: bridge_id, resource: resource, method: method, resource_id: resource_id})
      _ -> info("Unknown topic format: #{topic}")
    end
  end
  
  defp cast_to_hue_struct(attrs) do
    %Mqtt{}
    |> maybe_add_method(attrs)
    |> maybe_add_resource(attrs)
    |> maybe_add_bridge(attrs)
  end

  defp maybe_add_method(hue_struct, attrs) do
    case Map.fetch(attrs, :method) do
      {:ok, method} when method in @methods_list -> Map.put(hue_struct, :method, maybe_to_atom(method))
      {:ok, method} -> add_error_to_hue_struct(hue_struct, "unknown method #{method}")
      :error -> Map.put(hue_struct, :method, :get)
    end
  end
  
  defp maybe_add_bridge(hue_struct, attrs) when attrs.bridge_id == :default,
    do:  Map.put(hue_struct, :bridge, Hue.Conf.get_bridge())
  
  defp maybe_add_bridge(hue_struct, attrs) do
    case Hue.Conf.get_bridge(attrs.bridge_id) do
      nil -> add_error_to_hue_struct(hue_struct, "Can't find bridge in configuration")
      bridge -> Map.put(hue_struct, :bridge, bridge)
    end
  end

  defp maybe_add_resource(hue_struct, attrs) do
    if attrs.resource in Resource.resources_list() do
      hue_struct
      |> Map.put(:module, Resource.resource_to_module_name(attrs.resource))
      |> Map.put(:resource_id, attrs.resource_id)
    else
      hue_struct
      |> Map.put(:module, attrs.resource)
      |> add_error_to_hue_struct("Unkown resource, check API documentation for available resource list")
    end
  end

  @doc """
  Adds an error message to a Hue command structure and marks it as invalid.
  
  ## Parameters
  
  - `hue` - The %Mqtt{} struct to add error to
  - `error` - Error message string
  
  ## Returns
  
  Updated %Mqtt{} struct with error added and valid? set to false.
  """
  @spec add_error_to_hue_struct(%Mqtt{}, String.t()) :: %Mqtt{}
  def add_error_to_hue_struct(%Mqtt{} = hue, error) do
    hue
    |> Map.put(:error, [error | hue.error])
    |> Map.put(:valid?, false)
  end
  
  defp maybe_to_atom(data) when is_atom(data), do: data
  defp maybe_to_atom(data) when is_bitstring(data), do: String.to_atom(data)
  defp maybe_to_atom(data), do: raise "Unknown type for #{inspect(data)}"
end
