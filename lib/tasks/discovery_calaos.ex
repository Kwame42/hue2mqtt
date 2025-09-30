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
  use  Log

  @valid_resource ["light", "grouped_light"]
  
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
    :values
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
    discover_hue(options)
    |> convert_to_calaos(options)
  end
  
  defp discover_hue(options) do
    @valid_resource
    |> Enum.reduce(%{}, fn module_name, acc ->
      value = apply(:"Elixir.Hue.Api.#{Hue.Api.Resource.resource_to_module_name(module_name)}", :get, [Hue.Conf.get_bridge()])
      Map.put(acc, module_name, Map.get(value, :response))
    end)
    |> maybe_out_lights(options)
    |> maybe_out_zone_and_room(options)
  end

  defp maybe_out_lights(hue, options) do
    case Keyword.fetch(options, :hue_lights) do
      {:ok, filename} when is_bitstring(filename) ->
	File.write!(filename, Jason.encode!(hue, pretty: true))
	hue
	
      :error -> hue
    end
  end

  defp maybe_out_zone_and_room(hue, options) do
    case Keyword.fetch(options, :hue_zones_and_rooms) do
      {:ok, filename} when is_bitstring(filename) ->
	data = ["zone", "room"]
	|> Enum.reduce(%{}, fn module_name, acc ->
	  value = apply(:"Elixir.Hue.Api.#{Hue.Api.Resource.resource_to_module_name(module_name)}", :get, [Hue.Conf.get_bridge()])
	  Map.put(acc, module_name, Map.get(value, :response))
	end) 

	File.write!(filename, Jason.encode!(data, pretty: true))
	hue
	
      :error -> hue
    end
  end
	
  
  def convert_to_calaos(hue, options) do
    filename = get_filename(options)
    start = Keyword.get(options, :id_start, 0)

    hue
    |> Map.keys()
    |> Enum.reduce([], fn key, acc ->
      case Map.fetch(hue, key) do
	{:ok, resources} when not is_nil(resources) ->
	  [resources |> Enum.map(fn resource -> {key, resource} end)
	   | acc]
	  
	_ -> acc
      end
    end)
    |> List.flatten()
    |> Enum.reduce({[], start}, fn
      {resource, {"data", objects_list}}, {calaos, id} ->
	{calaos_list, last_id} = create_calaos_objects_list(resource, objects_list, id, hue)
        {calaos ++ calaos_list, last_id}

      _any, acc -> acc
    end)
    |> elem(0)
    |> Enum.reduce("", fn resource, data ->
      data <> render(resource) <> "\n"
    end)
    |> write_to_file(filename)
  end

  defp create_calaos_objects_list(resource, objects_list, start_id, hue) do
    Enum.reduce(objects_list, {[], start_id}, fn object, {calaos_list, id} ->
      attrs =
	%{"calaos_id" => id, "resource" => resource}
        |>  Map.merge(object)

      {_, new_calaos_list} =
	attrs 
	|> create_calaos(hue)
	|> maybe_add_light(attrs)
	|> maybe_add_dimmed_light(attrs)
	|> maybe_add_color_light(attrs)

      new_id =
	new_calaos_list
	|> List.last()
	|> Map.get(:calaos_id, id)
	
      {calaos_list ++ new_calaos_list, new_id}
    end)
  end

  defp create_calaos(attr, hue) do
    resource = Map.get(attr, "resource")
    id = Map.get(attr, "id")
    topic_sub = "hue2mqtt/#{resource}/#{id}"
    {
      %Calaos{
	id: "io_#{id}",
	resource: resource,
	data: ~S"{&quot;on&quot;: {&quot;on&quot;: __##VALUE##__}}",
	topic_sub: topic_sub,
	topic_pub: topic_sub <> "/set",
	name: get_resource_name(attr, hue),
	calaos_id: Map.get(attr, "calaos_id")
      },
      []
    }
  end

  defp get_resource_name(%{"metadata" => %{"name" => name}}, _hue) when not is_nil(name),
    do: name
    
  defp get_resource_name(%{"type" => "grouped_light", "owner" => %{"rid" => rid, "rtype" => rtype}}, hue) do
    with rtype in @valid_resource,
	 {:ok, data_type} when not is_nil(rtype) and not is_nil(data_type) <- Map.fetch(hue, rtype),
	 type <- Map.get(data_type, "data"),
	 rresource when not is_nil(rresource) <- Enum.find(type, fn %{"id" => id} -> id == rid end),
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

  @lights_list ["grouped_light", "light"]
  defp maybe_add_light({%Calaos{} = calaos, calaos_list}, %{"resource" => type}) when type in @lights_list do
    new_calaos =
      calaos
      |> increment_id()
      |> Map.put(:data, "{&quot;on&quot;: {&quot;on&quot;: __##VALUE##__}}")
      |> Map.put(:name, Map.get(calaos, :name) <> " (on/off)")
      |> Map.put(:type, "MqttOutputLight")
      |> Map.put(:path, "on/on")
      |> Map.put(:values, %{"off_value" => "false", "on_value" => "true"})
    
    {calaos, calaos_list ++ [new_calaos]}
  end
  
  defp maybe_add_light(accumulator, _),
    do: accumulator
  
  defp maybe_add_dimmed_light({%Calaos{} = calaos, calaos_list}, %{"dimming" => %{"brightness" => _}}) do
      new_calaos =
	calaos
	|> increment_id(List.last(calaos_list))
	|> Map.put(:data, "{&quot;dimming&quot;: {&quot;brightness&quot;: __##VALUE##__}}")
	|> Map.put(:name, Map.get(calaos, :name) <> " (dimmed)")
	|> Map.put(:type, "MqttOutputLightDimmer")
	|> Map.put(:path, "dimming/brightness")
	
    {calaos, calaos_list ++ [new_calaos]}
  end
  
  defp maybe_add_dimmed_light(accumulator, _),
    do: accumulator
  
  defp maybe_add_color_light({%Calaos{} = calaos, calaos_list}, %{"color_temperature" => _}) do
    new_calaos =
      calaos
      |> increment_id(List.last(calaos_list))
      |> Map.put(:data, "{&quot;color&quot;:{&quot;xy&quot;:{&quot;x&quot;:__##VALUE_X##__,&quot;y&quot;:__##VALUE_Y##__}}}")
      |> Map.put(:name, Map.get(calaos, :name) <> " (color)")
      |> Map.put(:type, "MqttOutputLightRGB")
      |> Map.put(:values, %{"path_x" => "color/xy/x", "path_y" => "color/xy/y"})
    
    {calaos, calaos_list ++ [new_calaos]}
  end
  
  defp maybe_add_color_light(accumulator, _),
    do: accumulator
  
  defp increment_id(%Calaos{calaos_id: _id} = calaos),
    do: increment_id(calaos, nil)
  
  defp increment_id(%Calaos{calaos_id: _id} = calaos, nil),
    do: Map.update!(calaos, :calaos_id, &(&1 + 1))

  defp increment_id(%Calaos{} = calaos, last_calaos),
    do: Map.update!(calaos, :calaos_id, fn _ -> Map.get(last_calaos, :calaos_id) + 1 end)
  
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
    values =
      case Map.fetch(assigns, :values) do
	{:ok, values} when is_map(values) ->
	  values
	  |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
	  |> Enum.join(" ")
	  
	_ -> ""
      end

    path =
      case Map.fetch(assigns, :path) do
	{:ok, path} when is_bitstring(path) -> "path=\"#{path}\""
	_ -> ""
      end
    
    ~s"""
    <calaos:output data='#{assigns.data}' enabled="true" gui_type="light" id="#{assigns.calaos_id}" io_type="output" log_history="true" logged="true" name="#{assigns.name}" #{values} #{path} topic_pub="#{assigns.topic_pub}" topic_sub="#{assigns.topic_sub}" type="#{assigns.type}" visible="true" />
    """
  end
end
