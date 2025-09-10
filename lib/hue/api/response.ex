defmodule Hue.Api.Response do
  @moduledoc """
  Response tracking and rate limiting for Hue API requests.
  
  This module manages HTTP response state including:
  - Request success/failure tracking
  - Rate limiting and retry logic
  - Timestamp management for API calls
  - Request count and error handling
  
  Each response tracks its URI, success status, retry counts, and timing
  information to ensure compliance with Hue bridge API rate limits.
  """
  
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

  @doc """
  Creates a new response tracking struct for a URI.
  
  ## Parameters
  
  - `uri` - URI being tracked
  - `timestamps_options` - Options for timestamp management
  
  ## Returns
  
  New %Response{} struct initialized for the URI.
  """
  @spec new(URI.t(), any()) :: %Response{}
  def new(uri, timestamps_options) do
    %Hue.Api.Response{
      uri: uri,
      success?: false,
      response: nil,
      timestamps: %{Timestamp.key(uri, timestamps_options) => Timestamp.new(timestamps_options)}
    }
  end
  
  @doc """
  Updates response struct with new attributes.
  
  ## Parameters
  
  - `response` - Response struct to update
  - `attrs` - Map of attributes to merge
  
  ## Returns
  
  Updated %Response{} struct.
  """
  @spec update_response(%Response{}, map()) :: %Response{}
  def update_response(%Response{} = response, attrs),
    do: Map.merge(response, attrs)

  @doc """
  Updates timestamp information for rate limiting.
  
  ## Parameters
  
  - `response` - Response struct to update
  - `timestamps_options` - Timestamp configuration options
  
  ## Returns
  
  Response struct with updated timestamps.
  """
  @spec update_timestamp(%Response{}, any()) :: %Response{}
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
  
  @doc """
  Gets response struct from API state by URI.
  
  ## Parameters
  
  - `api` - API state containing bridges map
  - `uri` - URI struct to look up
  
  ## Returns
  
  Response struct for the URI, raises if not found.
  """
  @spec get_response_from_uri!(map(), URI.t()) :: %Response{}
  def get_response_from_uri!(api, %URI{} = uri) do
    case Map.fetch(api.bridges, uri.host) do
      {:ok, response} -> Map.put(response, :uri, uri)
      :error -> raise "can't find host in api struct!"
    end
  end
  
  @spec get_response_from_uri!(map(), String.t()) :: %Response{}
  def get_response_from_uri!(api, url),
    do: get_response_from_uri!(api, URI.parse(url))

  @doc """
  Gets timestamp information for a response.
  
  ## Parameters
  
  - `response` - Response struct
  
  ## Returns
  
  Timestamp struct for rate limiting.
  """
  @spec get_timestamp_from_response(%Response{}) :: %Timestamp{} | nil
  def get_timestamp_from_response(response) do
    case Map.fetch(response.timestamps, response.uri.path) do
      {:ok, timestamp} -> timestamp
      _ -> Map.get(response.timestamps, "default")
    end
  end

  @doc """
  Waits if rate limiting is active and updates response for next call.
  
  ## Parameters
  
  - `response` - Response struct that may need waiting
  
  ## Returns
  
  Updated response struct ready for next call.
  """
  @spec maybe_wait_and_update(%Response{}) :: %Response{}
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
