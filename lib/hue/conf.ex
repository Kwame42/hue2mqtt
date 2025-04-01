defmodule Hue.Conf do
  use GenServer
  use Log
  alias Hue.Conf.Bridge

  @enforce_keys [:bridges_list]
  @discovery_url Application.compile_env!(:hue_mqtt, :api) |> Keyword.get(:discovery_url) || "https://discovery.meethue.com"
  defstruct [
    bridges_list: %{},
    auto_discovery: true,
    discovery_url: @discovery_url,
#    valid?: false
  ]

  defguard is_non_nul_string(string) when is_bitstring(string) and string != ""
  
  def start_link(_default),
    do: GenServer.start_link(__MODULE__, %{}, name: Hue.Conf)
  
  def update(%Hue.Conf.Bridge{} = bridge),
    do: GenServer.call(Hue.Conf, {:update, bridge})

  def get_conf,
    do: GenServer.call(Hue.Conf, :list)
  
  def get_bridge do
    get_conf()
    |> Map.get(:bridges_list)
    |> Map.to_list()
    |> List.first
    |> elem(1)
  end
    
  def get_bridge(id),
    do: GenServer.call(Hue.Conf, {:get, id})

  def list_bridges do
    get_conf()
    |> Map.get(:bridges_list)
  end

  @impl true
  def init(_config) do
    cond do
      not is_nil(Application.get_env(:hue_mqtt, :config_file)) ->
	info("Try to load conf from config map - see toml")
	Application.get_env(:hue_mqtt, :config_file)
	|> config_file_to_config_map()
	|> config_map_to_conf()
	
      is_list(Application.get_env(:hue_mqtt, :bridges_list)) ->
	info("Try to load conf from config.ex - -")
	{:ok, %Hue.Conf{bridges_list: Bridge.to_hue_struct(Application.get_env(:hue_mqtt, :bridges_list))}}
	
      true -> 
	info("Try to load conf in autodiscoery")
	{:ok, %Hue.Conf{bridges_list: maybe_auto_discover_briges_list()}}
    end
    |> validate_configuration()
  end

  @impl true
  def handle_call(:list, _from, config),
    do: {:reply, config, config}

  def handle_call({:update, %Hue.Conf.Bridge{} = bridge}, _from, config) do
    new_config = Map.put(config, :bridges_list, Map.update(config.bridges_list, bridge.id, bridge, &Map.merge(&1, bridge)))
    
    {:reply, new_config, new_config}
  end
  
  def handle_call({:get, id}, _from, config),
    do: {:reply, Map.get(config.bridges_list, id), config}

  def maybe_auto_discover_briges_list do
    with auto_discovery when auto_discovery != false <- :hue_mqtt |> Application.fetch_env!(:api) |> Keyword.get(:auto_discovery),
	 api when api.success? == true and is_list(api.response) <- Hue.Api.get_from_url(@discovery_url) do
      Hue.Conf.Bridge.to_bridge_struct(api.response)
    else
      _ -> []
    end
    |> Enum.reduce(%{}, fn bridge, acc ->
      Map.put(acc, bridge.id, bridge)
    end)
  end

  def write_conf(config_file) do
    bridges_list =
      get_conf()
      |> Map.get(:bridges_list)
      |> Enum.reduce([], fn {_key, val}, acc -> [val | acc] end)
      |> Jason.encode!()

    File.write(config_file, bridges_list)
  end

  def read_conf(config_file) do
    conf =
      config_file
      |> File.read!()
      |> Jason.decode!()
    
    if not is_list(conf),
      do: raise "There is a problem with your hue data file here: #{config_file} should be a list of bridges"
    
    conf
  end

  def load_config(config_file) do
    {:ok, %Hue.Conf{bridges_list: read_conf(config_file) |> Bridge.to_hue_struct()}}
  end

  def config_map_to_conf(toml) do
    bridges_list =
      toml
      |> Map.get("hue")
      |> Bridge.to_bridge_struct()
      |> List.wrap()
      |> Enum.reduce(%{}, fn bridge, map ->
        Map.put(map, bridge.id, bridge)
      end)

    {:ok, %Hue.Conf{bridges_list: bridges_list, auto_discovery: false}}
  end

  def config_file_to_config_map(config_file),
    do: Toml.decode_file!(config_file)

  @switches_list [
    {[hue_config: :string], "Hue Config file path - default: data/gue.config"},
    {[mqtt_config: :string], "MQTT Config file path - default: data/mqtt.config"},
    {[toml_config: :string], "TOML config file with hue and mqtt configuration"},
    {[io_output_file: :string], "Calaos IO output filename"},
    {[id_start: :integer], "Calaos IO id starting number - default is 0"},
    {[help: :boolean], "this message"}
  ]
  
  defp switches_list,
    do: Enum.map(@switches_list, &elem(&1, 0)) |> List.flatten()
  
  def application_load_config_in_env(args) do
    OptionParser.parse(args, switches: switches_list())
    |> application_load_config()
  end
  
  defp application_load_config({options, _, _}) do
    if Keyword.fetch(options, :help) != :error,
      do: help_and_exit()
      
    case Keyword.fetch(options, :toml_config) do
      {:ok, config_file} ->
	Application.put_env(:hue_mqtt, :config_file, config_file)
	
      :error ->
	hue_config = Keyword.get(options, :hue_config, "data/hue-config.json")
	mqtt_config = Keyword.get(options, :mqtt_config, "data/mqtt.config")
	Application.put_env(:hue_mqtt, :hue_config, hue_config)
	Application.put_env(:hue_mqtt, :mqtt_config, mqtt_config)
    end

    options
  end

  def help_and_exit() do
    options =
      @switches_list
      |> Enum.reduce("", fn {switch, message}, acc ->
      opt =
	switch
      	|> Keyword.keys()
	|> List.first()
	|> Atom.to_string
	|> String.replace("_", "-")
	
      acc <> " --#{String.replace(opt, "_", "-")}: #{message}\n"
    end)
    
    """
    Usage: hue2mqtt [options]

    Options:
    #{options}
    """
    |> IO.puts()
    System.halt(0)
  end

  defp configuration_error do
    error("Configuration is invalid, check existance of bridge username, or configuraiton file")
    help_and_exit()
  end

  defp validate_configuration({:ok, %Hue.Conf{} = configuration}) do
    with {:ok, bridges_list} when is_map(bridges_list) <- Map.fetch(configuration, :bridges_list) do
      bridges_list
      |> Enum.map(fn
	{_, %Hue.Conf.Bridge{} = bridge} when is_non_nul_string(bridge.username) -> :ok
	_ -> configuration_error()
      end)
    else
      _ -> configuration_error()
    end

    {:ok, configuration}
  end

  defp validate_configuration(_),
    do: configuration_error()
end
