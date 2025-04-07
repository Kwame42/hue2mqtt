defmodule Mqtt do
  @moduledoc """
  information on MQTT
  """

  use GenServer
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
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: Mqtt)
  end
  
  def init([]) do
    info("MQTT connection")
    emqtt_opts = load_config()
    {:ok, pid} = :emqtt.start_link(emqtt_opts)
    {:ok, %{pid: pid}, {:continue, :start_emqtt}}
  end

  def handle_continue(:start_emqtt, %{pid: pid} = opt) do
    {:ok, _} = :emqtt.connect(pid)
    {:ok, _, _} = :emqtt.subscribe(pid, {"hue2mqtt/#", 1})
    {:noreply, opt}
  end
    
  def handle_info({:publish, %{topic: topic, payload: payload}}, opt) do
    topic
    |> topic_to_hue()
    |> hue_bridge(payload)
    
    {:noreply, opt}
  end

  def handle_info(any, opt) do
    warning("MQTT (handle_info -default-): (#{inspect(any)}")
    {:noreply, opt}
  end

  def handle_call(%{payload: payload} = data, from, info) when not is_bitstring(payload) do
    data
    |> Map.put(:payload, Jason.encode!(payload))
    |> handle_call(from, info)
  end
  
  def handle_call(%{topic: topic, payload: payload}, _from, %{pid: pid}) do
    info("Publishing to topic #{topic}, payload #{inspect(payload)}")
    res = :emqtt.publish(pid, topic, payload, :qos0)
    {:reply, res, %{pid: pid}}
  end
  
  defp hue_bridge(%Mqtt{} = hue, _payload) when hue.valid? == false,
    do: error("Mqtt HUE error [#{hue.bridge_id}, #{hue.module}, #{hue.method}]: #{hue.error |> Enum.intersperse("\n") |> List.to_string()}")

  defp hue_bridge(%Mqtt{method: :put} = hue, payload) do
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

  def publish_to_mqtt(topic, payload) do
    GenServer.call(Mqtt, %{topic: "hue2mqtt/#{topic}", payload: payload})
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
	
      File.exists?(Application.get_env(:hue_mqtt, :mqtt_config)) ->
	info("Try to load conf from file")
	Hue.Conf.read_conf(Application.get_env(:hue_mqtt, :mqtt_config))
      true -> raise "no mqtt configuration availabel, add a config file"
    end
  end

  defp config_map_to_conf(config_map) do
    conf =
      config_map
      |> Map.get("mqtt")
      |> to_keyword()
    
    [port: 1883, clean_start: false, name: :emqtt]
    |> Keyword.merge(conf)
  end
  
  defp to_keyword(map) do
    Enum.reduce(map, [], fn {key, val}, list ->
      Keyword.put(list, String.to_atom(key), val)
    end)
  end

  @methods_list ["get", "put"]
  def topic_to_hue(topic) do
    case String.split(topic, "/") do
      ["hue2mqtt", resource, resource_id] -> cast_to_hue_struct(%{bridge_id: :default, resource: resource, resource_id: resource_id})
      ["hue2mqtt", resource, resource_id, method] when method in @methods_list-> cast_to_hue_struct(%{bridge_id: :default, resource: resource, method: method, resource_id: resource_id})
      ["hue2mqtt", bridge_id, resource, resource_id] -> cast_to_hue_struct(%{bridge_id: bridge_id, resource: resource, resource_id: resource_id})
      ["hue2mqtt", bridge_id, resource, resource_id, method] when method in @methods_list -> cast_to_hue_struct(%{bridge_id: bridge_id, resource: resource, method: method, resource_id: resource_id})
      _ -> info("get topic #{topic}")
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

  def add_error_to_hue_struct(%Mqtt{} = hue, error) do
    hue
    |> Map.put(:error, [error | hue.error])
    |> Map.put(:valid?, false)
  end
  
  defp maybe_to_atom(data) when is_atom(data), do: data
  defp maybe_to_atom(data) when is_bitstring(data), do: String.to_atom(data)
  defp maybe_to_atom(data), do: raise "Unknown type for #{inspect(data)}"
end
