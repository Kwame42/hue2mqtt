defmodule Hue.Api.Response.Timestamp do
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

  def new,
    do: %Timestamp{updated_at: NaiveDateTime.utc_now()}
  
  def new(nil),
    do: %Timestamp{updated_at: NaiveDateTime.utc_now()}
  
  def new(timestamps_attrs),
    do: Map.merge(%Timestamp{updated_at: NaiveDateTime.utc_now()}, Map.new(timestamps_attrs))
  
  def key(_, nil),
    do: "default"
  
  def key(%URI{} = uri, _),
    do: uri.path

  def sleep(diff) when not is_integer(diff) or diff < 0 or diff > 2000,
    do: Logger.warning("there is an issue with diff check it please ! #{diff}")

  def sleep(diff) do
    id = Enum.random(1_000..9_999)
    Logger.warning("[#{id} - #{NaiveDateTime.utc_now() |> inspect()}] sleeping for  #{diff + 1}")
    :timer.sleep(diff + 1)
    Logger.warning("[#{id} - #{NaiveDateTime.utc_now() |> inspect()}] wakeup!")
  end
  
  
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

  def add_count(%Timestamp{} = timestamp, num \\ 1),
    do: Map.put(timestamp, :count, timestamp.count + num)
end
