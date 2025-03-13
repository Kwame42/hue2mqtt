defmodule Hue.Api.Response do
  require Logger
  
  alias Hue.Api.Response
  alias Hue.Api.Response.Timestamp
  
  defstruct [
    updated_at: nil,
    call?: true,
    count: 0,
    next_call: nil,
    error: nil,
    success?: false,
    uri: nil,
    response: nil,
    timestamps: %{},
  ]

  def new(uri, timestamps_options) do
    %Hue.Api.Response{
      uri: uri,
      success?: false,
      response: nil,
      timestamps: %{Timestamp.key(uri, timestamps_options) => Timestamp.new(timestamps_options)}
    }
  end
  
  def update_response(%Response{} = response, attrs),
    do: Map.merge(response, attrs)

  def update_timestamp(%Response{} = response, timestamps_options) do
    response
    |> Map.update!(:timestamps, fn timestamps ->
      key = Timestamp.key(response.uri, timestamps_options)
      val =
	case Map.fetch(timestamps, key) do
	  {:ok, timestamp} -> Timestamp.check_and_update(timestamp)
	  _ -> Timestamp.new(timestamps_options)
	end
	
      Map.put(timestamps, key, val)
    end)
  end
  
  def get_response_from_uri!(api, %URI{} = uri) do
    case Map.fetch(api.bridges, uri.host) do
      {:ok, response} -> Map.put(response, :uri, uri)
      :error -> raise "can't find host in api struct!"
    end
  end
  
  def get_response_from_uri!(api, url),
    do: get_response_from_uri!(api, URI.parse(url))

  def get_timestamp_from_response(response) do
    case Map.fetch(response.timestamps, response.uri.path) do
      {:ok, timestamp} -> timestamp
      _ -> Map.get(response.timestamps, "default")
    end
  end

  def maybe_wait_and_update(response) when not is_nil(response.next_call) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.diff(response.next_call, :millisecond)
    |> Timestamp.sleep()
    
    attrs = %{
      call?: true,
      count: 0
    }

    Response.update_response(response, attrs)
  end

  def maybe_wait_and_update(response),
    do: response
end
