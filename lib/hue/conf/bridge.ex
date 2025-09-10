defmodule Hue.Conf.Bridge do
  @moduledoc """
  Bridge configuration struct and utility functions for Hue bridge management.
  
  This module defines the Bridge struct used to store Hue bridge connection
  parameters and provides functions for:
  - Converting various input formats to Bridge structs
  - Building URLs and headers for HTTP requests
  - Managing bridge authentication credentials
  - Handling multiple bridge configurations
  """
  
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

  @doc """
  Converts various input formats to a Bridge struct.
  
  ## Parameters
  
  - `attrs` - Map with bridge attributes including :id (required)
  
  ## Returns
  
  %Bridge{} struct with populated fields.
  """
  @spec to_bridge_struct(map()) :: %Bridge{}
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

  @doc """
  Converts bridge attribute maps to a keyed collection of Bridge structs.
  
  ## Parameters
  
  - `attrs` - List or map of bridge attributes
  
  ## Returns
  
  Map of bridge_id => %Bridge{} struct.
  """
  @spec to_hue_struct([map()] | map()) :: %{any() => %Bridge{}}
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

  @doc """
  Builds a complete URL for the bridge API endpoint.
  
  ## Parameters
  
  - `bridge` - Bridge struct with IP and port
  - `path` - API path to append (optional)
  
  ## Returns
  
  Complete HTTPS URL string for the bridge endpoint.
  """
  @spec url(%Bridge{}, String.t()) :: String.t()
  def url(%Bridge{} = bridge, path \\ "") do
    ~s"""
    https://#{bridge.ip}:#{bridge.port}/#{String.trim_leading(path, "/")}
    """
    |> String.trim()
  end

  @doc """
  Builds HTTP headers for bridge API requests including authentication.
  
  ## Parameters
  
  - `bridge` - Bridge struct with username for auth
  - `headers` - Additional headers to include (optional)
  
  ## Returns
  
  List of HTTP header tuples with authentication header added.
  """
  @spec headers(%Bridge{}, list()) :: list()
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
