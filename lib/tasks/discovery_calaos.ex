defmodule Mix.Tasks.Discovery.Calaos do
  alias Mix.Tasks.Discovery.Calaos
  alias Hue.Conf
  
  use Mix.Task
  defstruct [
    :id,
    :resource,
    :calaos_id,
    :data,
    :topic_pub,
    :topic_sub,
    :name,
  ]
  
  def run(args) do
    Application.ensure_all_started(:httpoison)
    options = Conf.application_load_config_in_env(args)
    Application.ensure_all_started(:hue_mqtt)
    discover_hue()
    |> convert_to_calaos(options)
  end

  def convert_to_calaos(hue, options) do
    filename = get_filename(options)
    start = Keyword.get(options, :id_start, 0)

    hue
    |> Map.keys()
    |> Enum.reduce([], fn key, acc ->
      [ hue
      |> Map.get(key)
      |> Enum.map(fn resource -> {key, resource} end) |
	acc]
    end)
    |> List.flatten()
    |> Enum.with_index(start)
    |> Enum.map(fn {{resource, object}, id} ->
      %{"calaos_id" => "id_#{Integer.to_string(id)}", "resource" => resource}
      |> Map.merge(object)
      |> create_calaos()
    end)
    |> Enum.reduce("", fn resource, data ->
      data <> render(resource) <> "\n"
    end)
    |> write_to_file(filename)
  end

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
  
  defp discover_hue do
    ["light", "room", "grouped_light"]
    |> Enum.reduce(%{}, fn module_name, acc ->
      value = apply(:"Elixir.Hue.Api.#{Hue.Api.Resource.resource_to_module_name(module_name)}", :get, [Hue.Conf.get_bridge()])
      Map.put(acc, module_name, Map.get(value, :response))
    end)
  end
  
  defp create_calaos(attr) do
    resource = Map.get(attr, "resource")
    id = Map.get(attr, "id")
    topic_sub = "hue2mqtt/#{resource}/#{id}"
    %Calaos{
      id: "io_#{id}",
      resource: resource,
      data: Map.get(attr, "a", "default"),
      topic_sub: topic_sub,
      topic_pub: topic_sub <> "/set",
      name: Map.get(attr, "name"),
      calaos_id: Map.get(attr, "calaos_id")
    }
  end
  
  def render(assigns) do
    ~s"""
    <calaos:output data='#{assigns.data}' enabled="true" gui_type="light" id="#{assigns.calaos_id}" io_type="output" log_history="true" logged="true" name="#{assigns.name}" off_value="false" on_value="true" path="state/on" topic_pub="#{assigns.topic_pub}" topic_sub="#{assigns.topic_sub}" type="MqttOutputLight" visible="true" />
    """
  end
end
