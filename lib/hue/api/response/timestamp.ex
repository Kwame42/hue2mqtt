defmodule Hue.Api.Response.Timestamp do
  @moduledoc """
  Rate limiting timestamp management for Hue API requests.
  
  This module tracks request timing and counts to ensure compliance with
  Hue bridge API rate limits. It manages:
  - Request count tracking per time interval
  - Automatic rate limit enforcement
  - Sleep intervals when limits are exceeded
  - Per-endpoint timestamp tracking
  """
  
  alias Hue.Api.Response.Timestamp
  require Logger
  
  defstruct [
    updated_at: nil, 
    count: 0,
    max_requests: 10,
    interval: 1_000, # in milliseconds
    call?: true,
    success?: false
  ]

  @doc """
  Creates a new timestamp with default settings.
  
  ## Returns
  
  %Timestamp{} struct with current time and default rate limits.
  """
  @spec new() :: %Timestamp{}
  def new,
    do: %Timestamp{updated_at: NaiveDateTime.utc_now()}
  
  @doc """
  Creates a new timestamp, handling nil input.
  """
  @spec new(nil) :: %Timestamp{}
  def new(nil),
    do: %Timestamp{updated_at: NaiveDateTime.utc_now()}
  
  @doc """
  Creates a new timestamp with custom attributes.
  
  ## Parameters
  
  - `timestamps_attrs` - Custom attributes for the timestamp
  
  ## Returns
  
  %Timestamp{} struct with merged attributes.
  """
  @spec new(keyword() | map()) :: %Timestamp{}
  def new(timestamps_attrs),
    do: Map.merge(%Timestamp{updated_at: NaiveDateTime.utc_now()}, Map.new(timestamps_attrs))
  
  @doc """
  Generates a key for timestamp tracking.
  
  ## Parameters
  
  - `uri` - URI for the request (ignored if options is nil)
  - `options` - Configuration options (nil returns "default")
  
  ## Returns
  
  String key for timestamp tracking.
  """
  @spec key(any(), any()) :: String.t()
  def key(_, nil),
    do: "default"
  
  @spec key(URI.t(), any()) :: String.t()
  def key(%URI{} = uri, _),
    do: uri.path

  @doc """
  Sleeps for a specified duration with validation and logging.
  
  ## Parameters
  
  - `diff` - Sleep duration in milliseconds
  """
  @spec sleep(integer()) :: :ok
  def sleep(diff) when not is_integer(diff) or diff < 0 or diff > 2000,
    do: Logger.warning("there is an issue with diff check it please ! #{diff}")

  @spec sleep(integer()) :: :ok
  def sleep(diff) do
    id = Enum.random(1_000..9_999)
    Logger.warning("[#{id} - #{NaiveDateTime.utc_now() |> inspect()}] sleeping for  #{diff + 1}")
    :timer.sleep(diff + 1)
    Logger.warning("[#{id} - #{NaiveDateTime.utc_now() |> inspect()}] wakeup!")
  end
  
  
  @doc """
  Updates timestamp based on rate limiting rules.
  
  ## Parameters
  
  - `timestamp` - Timestamp struct to check and update
  - `num` - Number of requests to add (default: 1)
  
  ## Returns
  
  Updated %Timestamp{} struct with new counts and call status.
  """
  @spec check_and_update(%Timestamp{}, integer()) :: %Timestamp{}
  def check_and_update(%Timestamp{} = timestamp, num \\ 1) do
    now = NaiveDateTime.utc_now()
    cond do
      NaiveDateTime.diff(now, timestamp.updated_at, :millisecond) > timestamp.interval ->
	timestamp
	|> Map.put(:updated_at, now)
	|> Map.put(:count, num)
	|> Map.put(:call?, true)
	
      timestamp.count < timestamp.max_requests ->
	timestamp
	|> Map.put(:count, timestamp.count + num)
	|> Map.put(:call?, true)

      timestamp.count >= timestamp.max_requests ->
	timestamp
	|> Map.put(:count, timestamp.count + num)	
	|> Map.put(:call?, false)

      true -> timestamp
    end
  end

  @doc """
  Adds to the request count of a timestamp.
  
  ## Parameters
  
  - `timestamp` - Timestamp struct to update
  - `num` - Number to add to count (default: 1)
  
  ## Returns
  
  Updated %Timestamp{} struct with incremented count.
  """
  @spec add_count(%Timestamp{}, integer()) :: %Timestamp{}
  def add_count(%Timestamp{} = timestamp, num \\ 1),
    do: Map.put(timestamp, :count, timestamp.count + num)
end
