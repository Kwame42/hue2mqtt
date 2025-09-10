defmodule Mix.Tasks.Discovery.Calaos do
  @moduledoc """
  Mix task for discovering Hue devices and generating Calaos configuration.
  
  This task connects to configured Hue bridges, discovers available devices,
  and generates Calaos home automation system configuration files (io.xml).
  
  It supports discovery of:
  - Lights and grouped lights
  - Rooms and zones  
  - Sensors and other supported devices
  
  ## Usage
  
      mix discovery.calaos [global_options] [calaos_options]
  
  ## Global Options
  
  - `--hue-config` - Hue configuration file path
  - `--mqtt-config` - MQTT configuration file path  
  - `--toml-config` - Combined TOML configuration file
  
  ## Calaos Options
  
  - `--io-output-file` - Output filename for Calaos IO configuration
  - `--id-start` - Starting ID number for Calaos devices (default: 0)
  """
  
  alias Mix.Tasks.Discovery.Calaos
  alias Hue.Conf

  @valid_resource ["light", "room", "grouped_light", "zone"]
  
  use Mix.Task
  defstruct [
    :id,
    :resource,
    :calaos_id,
    :data,
    :topic_pub,
    :topic_sub,
    :name,
    :type,
  ]
  
  @doc """
  Runs the Calaos discovery task.
  
  ## Parameters
  
  - `args` - Command-line arguments for configuration
  """
  @spec run([String.t()]) :: :ok
  def run(args) do
    Application.ensure_all_started(:httpoison)
    options = Conf.application_load_config_in_env(args)
    Application.ensure_all_started(:hue_mqtt)
    discover_hue()
    |> convert_to_calaos(options)
  end
  
  defp discover_hue do
    @valid_resource
    |> Enum.reduce(%{}, fn module_name, acc ->
      value = apply(:"Elixir.Hue.Api.#{Hue.Api.Resource.resource_to_module_name(module_name)}", :get, [Hue.Conf.get_bridge()])
      Map.put(acc, module_name, Map.get(value, :response))
    end)
  end
  

  def convert_to_calaos(hue, options) do
    filename = get_filename(options)
    start = Keyword.get(options, :id_start, 0)

    hue
    |> Map.keys()
    |> Enum.reduce([], fn key, acc ->
      [hue
      |> Map.get(key)
      |> Enum.map(fn resource -> {key, resource} end) |
	acc]
    end)
    |> List.flatten()
    |> Enum.with_index(start)
    |> Enum.map(fn {{resource, object}, id} ->
      attrs =
	%{"calaos_id" => id, "resource" => resource}
        |>  Map.merge(object)

      attrs
      |> create_calaos(hue)
      |> maybe_add_light(attrs)
      |> maybe_add_dimmed_light(attrs)
      |> maybe_add_color_light(attrs)
    end)
    |> List.flatten()
    |> Enum.reduce("", fn resource, data ->
      data <> render(resource) <> "\n"
    end)
    |> write_to_file(filename)
  end
  
  defp create_calaos(attr, hue) do
    resource = Map.get(attr, "resource")
    id = Map.get(attr, "id")
    topic_sub = "hue2mqtt/#{resource}/#{id}"
    %Calaos{
      id: "io_#{id}",
      resource: resource,
      data: ~S"{&quot;on&quot;: {&quot;on&quot;: __##VALUE##__}}",
      topic_sub: topic_sub,
      topic_pub: topic_sub <> "/set",
      name: get_resource_name(attr, hue),
      calaos_id: Map.get(attr, "calaos_id")
    }
  end

  defp get_resource_name(%{"name" => name}, _hue) when not is_nil(name),
    do: name
  
  defp get_resource_name(%{"type" => "grouped_light", "owner" => %{"rid" => rid, "rtype" => rtype}}, hue) do
    with rtype when rtype in @valid_resource <- rtype,
	 rresource when not is_nil(rresource) <- hue |> Map.get(rtype) |> Enum.find(fn %{"id" => id} -> id == rid end),
	 {:ok, metadata} <- Map.fetch(rresource, "metadata"),
	 {:ok, name} <- Map.fetch(metadata, "name") do
      String.capitalize(rtype) <> " " <> name
    else
      _ -> "No name"
    end
  end

  defp get_resource_name(_attr, _) do
    "name"
  end

  defp maybe_add_light(%Calaos{} = calaos, %{"resource" => %{"type" => "light"}}),
    do: Map.put(calaos, :type, "MqttOutputLight")
  
  defp maybe_add_light(%Calaos{} = calaos, _),
    do: calaos
  
  defp maybe_add_dimmed_light(%Calaos{} = calaos, %{"resource" => %{"type" => "light", "dimming" => %{"brightness" => _}}}),
    do: Map.put(calaos, :type, "MqttOutputLightDimmer")
  
  defp maybe_add_dimmed_light(%Calaos{} = calaos, _),
    do: calaos
  
  defp maybe_add_color_light(%Calaos{} = calaos, %{"resource" => %{"type" => "light", "color_temperature" => _}}) do
    calaos
    |> increment_id()
    |> Map.put(:type, "MqttOutputLightRGB")
    |> Map.put(:data, "{&quot;xy&quot;: [__##VALUE_X##__,__##VALUE_Y##__]}")
    |> Map.put(:name, "name")
    
    """
    <calaos:output data="{&quot;xy&quot;: [__##VALUE_X##__,__##VALUE_Y##__]}" id="io_78" io_type="output" logged="true" name="CY cuisine hote (Color)" path="bri" topic_pub="hue2mqtt/light/00:17:88:01:0d:de:33:1e-0b/set" type="MqttOutputLightRGB"/>
    """
  end
  
  defp maybe_add_color_light(%Calaos{} = calaos, _),
    do: calaos
  
  defp increment_id(%Calaos{calaos_id: _id} = calaos),
    do: Map.update!(calaos, :calaos_id, &(&1 + 1))
  
  defp write_to_file(data, filename),
    do: File.write!(filename, data)

  def get_filename(opt) do
    case Keyword.fetch(opt, :io_output_file) do
      {:ok, filename} when is_bitstring(filename) -> filename
      :error -> raise "Can't find option --io-output-file"
    end
  end
  
  def get_init_id(opt) do
    with {:ok, id} when is_integer(id) <- Keyword.get(opt, :id_start, 0) do
      id
    else
      _ -> raise "can't start a that id, must be an integer"
    end
  end
  
  def render(assigns) do
    ~s"""
    <calaos:output data='#{assigns.data}' enabled="true" gui_type="light" id="#{assigns.calaos_id}" io_type="output" log_history="true" logged="true" name="#{assigns.name}" off_value="false" on_value="true" path="on/on" topic_pub="#{assigns.topic_pub}" topic_sub="#{assigns.topic_sub}" type="MqttOutputLight" visible="true" />
    """
  end
end
