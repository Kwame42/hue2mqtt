defmodule Mqtt do
  alias Mqtt
  @moduledoc """
  information on MQTT
  """

  use GenServer
  use Log
  alias Hue.Api.Resource

  defstruct do: [
    base: "hue2mqtt",
    bridge_id: "default",
    module_name: "",
    resource_id: "",
    module: "",
    method: :get,
    valid?: true,
    error: "",
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
  
  def hue_bridge(%Mqtt{} = hue, _payload) when not hue.valid?,
    do: warning("Mqtt HUE error: #{hue.error}[#{hue.resource}]")

  def hue_bridge(["hue2mqtt", resource, id, "set"], payload) do
    IO.inspect(Jason.decode(payload), label: "PAYLOAD")
    with resource in Resource.resources_list(),
	 {:ok, encoded_payload} <- Jason.decode(payload) do
      module_name = Resource.resource_to_module_name(resource) 
      info("Set HUE bridge ressource: [#{resource}/#{id}] (#{module_name}) with payload #{inspect payload}")
      apply(:"Elixir.Hue.Api.#{module_name}", :put, [Hue.Conf.get_bridge(), id, encoded_payload])
      |> info()
    else
      :error -> error("Payload: #{inspect(payload)} invalid, must be JSON type")
      false -> error("Unkown resource #{resource}")
    end
  end

  def hue_bridge(%Mqtt{} = hue, payload) do
    info("Set HUE bridge ressource: [#{hue.module_name}/#{hue.resource_id}] (#{hue.module_name}) with payload #{inspect payload}")
    apply(:"Elixir.Hue.Api.#{hue.module_name}", hue.method, [Hue.Conf.get_bridge(hue.bridge), hue.id, payload])
  end
  
  def hue_bridge(%Mqtt{} = hue, _payload) do
    info("MQTT HUE info [#{hue.module_name}, #{hue.resource_id}]") 
  end
  
  def hue_bridge(data, _) do
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

  def topic_to_hue(topic) do
    case String.split(topic, "/") do
      ["hue2mqtt", resource, resource_id] -> new_hue(%{bridge_id: "default", module: resource, resource_id: resource_id})
      ["hue2mqtt", resource, resource_id, "set"] -> new_hue(%{bridge_id: "default", module: resource, method: :put, resource_id: resource_id})
      ["hue2mqtt", bridge_id, resource, resource_id] -> new_hue(%{bridge_id: bridge_id, module: resource, resource_id: resource_id})
      ["hue2mqtt", bridge_id, resource, resource_id, "set"] -> new_hue(%{bridge_id: bridge_id, module: resource, method: :put, resource_id: resource_id})
    end
  end

  def new_hue(attrs, error) do
    if attrs.resource in Resource.resources_list do
      %Mqtt{
	bridge_id: attrs.bridge_id, 
	module: Resource.resource_to_module_name(attrs.resource),
	method: attrs.method,
	resource_id: attrs.resource_id
      }
    else
      error_hue("unkown ressource")
    end
  end

   def error_hue(%Mqtt{} = hue, error) do
     hue
     |> Map.put(:error, error)
     |> Map.put(valid?: false)
   end
   
   def error_hue(error),
     do: error_hue(%Mqtt{}, error)
end
