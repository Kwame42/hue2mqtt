defmodule Hue.Conf.Bridge do
  alias Hue.Conf.Bridge
  
  @derive {Jason.Encoder, only: [:id, :ip, :port, :username, :password, :status]}
  @enforce_keys [:id]
  defstruct [
    id: "",
    ip: "",
    port: 443,
    username: "",
    password: "",
    status: ""
  ]

  def to_bridge_struct(%{id: _id} = attrs) do
    %Bridge{
      id: map_get(attrs, :id),
      ip: map_get(attrs, :ip, :internalipaddress),
      port: map_get(attrs, :port) || 443,
      username: map_get(attrs, :username),
      password: map_get(attrs, :password),
      status: map_get(attrs, :status)
    }
  end

  def to_bridge_struct(list) when is_list(list) do
    list
    |> maybe_to_map_keys()
    |> Enum.map(&to_bridge_struct(&1))
  end
  
  def to_bridge_struct(%{"id" => _id} = attrs),
    do: attrs |> maybe_to_map_keys() |> to_bridge_struct()

  def to_bridge_struct(attrs) do
    attrs
    |> Map.put(:id, random_id())
    |> to_bridge_struct()
  end

  def to_hue_struct(attrs) do
    attrs
    |> maybe_to_map_keys()
    |> Enum.reduce(%{}, fn
      %{id: id} = bridge, bridges_list ->
	Map.put(bridges_list, id, to_bridge_struct(bridge))
      key, _ ->
	raise "You must have an id key to your bridge list #{inspect(maybe_to_map_keys(attrs))} - #{inspect(key)}"
    end)
  end

  def url(%Bridge{} = bridge, path \\ "") do
    ~s"""
    https://#{bridge.ip}:#{bridge.port}/#{String.trim_leading(path, "/")}
    """
    |> String.trim()
  end

  def headers(bridge, headers \\ []) when not is_nil(bridge.username),
    do: [{"hue-application-key", bridge.username} | headers]
  
  defp maybe_to_map_keys(map) when is_map(map) do
    map
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, new_map ->
      if is_bitstring(key) do
	Map.put(new_map, String.to_atom(key), Map.get(map, key))
      else
	Map.put(new_map, key, Map.get(map, key))
      end
    end)
  end
  
  defp maybe_to_map_keys(list) when is_list(list),
    do: Enum.map(list, &maybe_to_map_keys(&1))

  defp random_id do
    for _ <- 1..17, into: "", do: <<Enum.random(~c"0123456789abcdefghijklmnopqrstuvwxyz")>>
  end

  defp map_get(map, key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp map_get(map, key, alt),
    do: map_get(map, key) || map_get(map, alt)
end
