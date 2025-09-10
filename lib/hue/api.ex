defmodule Hue.Api do
  @moduledoc """
  HTTP API client for Philips Hue bridge communication with request throttling and retry logic.
  
  This GenServer manages HTTP communication with Hue bridges, implementing:
  - Request rate limiting and retry mechanisms
  - Response caching and timestamp tracking
  - Support for GET, PUT, POST, DELETE operations
  - Automatic handling of 429 (Too Many Requests) responses
  - SSL verification bypass for local bridge communication
  
  The module maintains connection state for multiple bridges and ensures
  API rate limits are respected through intelligent request throttling.
  """
  
  use GenServer
  use Log
  alias Hue.Conf.Bridge
  alias Hue.Api.Response
  alias Hue.Api.Response.Timestamp
  
  defstruct [bridges: %{}]
  
  @retries Application.compile_env!(:hue_mqtt, :api) |> Keyword.get(:retry) || 3

  @doc """
  Starts the Hue API GenServer.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_default),
    do: GenServer.start_link(__MODULE__, %{}, name: Hue.Api)
  
  @impl true
  def init(_config),
    do: {:ok, %Hue.Api{}}
  
  @impl true
  def handle_call({:http, :get, url, headers, _data, options}, _from, api),
    do: http_request(&HTTPoison.get/3, url, nil, headers, options, api)
  
  def handle_call({:http, :put, url, headers, data, options}, _from, api),
    do: http_request(&HTTPoison.put/4, url, data, headers, options, api)
  
  def handle_call({:http, :post, url, headers, data, options}, _from, api),
    do: http_request(&HTTPoison.post/4, url, data, headers, options, api)
  
  def handle_call({:http, :delete, url, headers, _data, options}, _from, api),
    do: http_request(&HTTPoison.delete/3, url, nil, headers, options, api)
  
  defp http_request(http_method_func, url, data, headers, options, api) do
    uri = URI.parse(url)
    api = update_or_create_api(uri, api, Keyword.get(options, :timestamp))
    response =
      api
      |> Response.get_response_from_uri!(uri)
      |> http_request_from_response(http_method_func, url, data, headers, @retries, options)
    
    new_api = add_response_to_bridges_list(response, api)
    {:reply, response, new_api}
  end

  defp http_request_from_response(response, http_method_func, url, data, headers, num, options) do
    response = Response.update_timestamp(response, Keyword.get(options, :timestamp))
    timestamp = Response.get_timestamp_from_response(response)
    do_http_request(response, timestamp,  http_method_func, url, data, headers, num, options)
  end
  
  defp do_http_request(response, _timestamp, _http_method_func, _url, _data, _headers, 0, _options),
    do: response
  
  defp do_http_request(response, _timestamp, http_method_func, url, data, headers, num, options) when not response.call? do
    response
    |> Response.maybe_wait_and_update()
    |> http_request_from_response(http_method_func, url, data, headers, num, options)
  end
  
  defp do_http_request(response, timestamp, http_method_func, url, data, headers, num, options) when not timestamp.call? do
    Timestamp.sleep(timestamp.interval)
    http_request_from_response(response, http_method_func, url, data, headers, num, options)
  end
  
  defp do_http_request(response, _timestamp, http_method_func, url, nil, headers, num, options) do
    http_method_func.(url, headers, http_options()) 
    |> set_api_response(response, http_method_func, url, nil, headers, num, options)
  end

  defp do_http_request(response, _timestamp, http_method_func, url, data, headers, num, options) do
    http_method_func.(url, data, headers, http_options()) 
    |> set_api_response(response, http_method_func, url, nil, headers, num, options)
  end

  defp set_api_response({:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers}}, response, _, _, _, _, _, _) do
    attrs = %{
      count: response.count + 1,
      success?: true,
      error: nil,
      response: build_body(body, headers)
    }

    Response.update_response(response, attrs)
  end

  defp set_api_response({:ok, %HTTPoison.Response{status_code: 429, headers: headers}}, response, _, _, _, _, _, _) do
    timeout = get_header(headers, "Retry-After")
    warning("Error 429, must wait #{response.uri.host} #{timeout}")
    attrs = %{
      last_call: DateTime.utc_now(),
      success?: false,
      call?: false,
      next_call: NaiveDateTime.add(NaiveDateTime.utc_now(), timeout, :seconds),
      error: :wait
    }

    Response.update_response(response, attrs)
  end
  
  defp set_api_response({:ok, %HTTPoison.Response{status_code: code, headers: headers, body: body}}, response, _, _, _, _, _, _) do
    warning("Http request error host:#{response.uri.host} error_code:#{code} error_body:#{body |> build_body(headers) |> inspect()})")
    attrs = %{
      count: response.count + 1,
      response: nil,
      success?: false,
      error: code
    }

    Response.update_response(response, attrs)
  end
  
  defp set_api_response(error, response, http_method_func, url, data, headers, num, options) do
    warning("Http request error (#{num}/#{@retries}: #{inspect(error)})")
    attrs =
      %{
	response: nil,
	success?: false,
	error: inspect(error)
      }

    response
    |> Response.update_response(attrs)
    |> http_request_from_response(http_method_func, url, data, headers, num - 1, options)
  end

  defp build_body(nil, _headers),
    do: nil
    
  defp build_body(body, headers) do
    if Enum.find(headers, &(elem(&1, 0) == "Content-Type" && elem(&1, 1) |> String.split(";") |> List.first == "application/json")) do
      json = Jason.decode!(body)
      if is_list(json) do
	json
      else
	data =
	  case Map.get(json, "data") do
	    nil -> Map.get(json, "errors")
	    data -> data
	  end
	
	case Enum.count(data) do
	  1 -> List.first(data)
	  _ -> data
	end
      end
    else
      body
    end
  end

  defp add_response_to_bridges_list(response, api),
    do: Map.put(api, :bridges, Map.put(api.bridges, response.uri.host, Map.put(response, :response, "")))
  
  defp update_or_create_api(uri, api, timestamps_options) do
    case Map.fetch(api.bridges, uri.host) do
      {:ok, response} -> Response.update_response(response, %{uri: uri})
      _ -> Response.new(uri, timestamps_options)
    end
    |> add_response_to_bridges_list(api)
  end
  
  @doc """
  Makes an HTTP request with specified method, URL, headers, and optional data.
  
  ## Parameters
  
  - `method` - HTTP method (:get, :put, :post, :delete)
  - `url` - Full URL to request
  - `headers` - HTTP headers list
  - `data` - Request body (optional, will be JSON encoded if map)
  - `options` - Additional options (optional)
  
  ## Returns
  
  HTTP response from the GenServer call.
  """
  @spec call(atom(), String.t(), list(), String.t() | map() | nil, keyword()) :: any()
  def call(method, url, headers, data \\ nil, options \\ [])

  def call(method, url, headers, data, options) when is_nil(data) or is_bitstring(data),
    do: GenServer.call(Hue.Api, {:http, method, url, headers, data, options})

  def call(method, url, headers, data, options) when is_map(data),
    do: call(method, url, headers, Jason.encode!(data), options)
  
  @doc """
  Makes a GET request to the specified URL.
  
  ## Parameters
  
  - `url` - URL to GET
  - `headers` - HTTP headers (optional)
  - `options` - Request options (optional)
  """
  @spec get_from_url(String.t(), list(), keyword()) :: any()
  def get_from_url(url, headers \\ [], options \\ []),
    do: call(:get, url, headers, nil,  options)

  @doc """
  Makes a GET request to the specified URL, raising on failure.
  
  ## Parameters
  
  - `url` - URL to GET
  - `headers` - HTTP headers (optional)
  - `options` - Request options (optional)
  
  ## Returns
  
  Response data on success, raises on failure.
  """
  @spec get_from_url!(String.t(), list(), keyword()) :: any()
  def get_from_url!(url, headers \\ [], options \\ []) do
    case get_from_url(url, headers, options) do
      {:ok, data} -> data
      _ -> raise "API error"
    end
  end

  @doc """
  Makes a GET request to a Hue bridge endpoint.
  
  ## Parameters
  
  - `bridge` - Bridge configuration struct
  - `path` - API path on the bridge
  - `headers` - Additional headers (optional)
  - `options` - Request options (optional)
  """
  @spec get_from_bridge(%Hue.Conf.Bridge{}, String.t(), list(), keyword()) :: any()
  def get_from_bridge(bridge, path, headers \\ [], options \\ []),
    do: get_from_url(Bridge.url(bridge, path), Bridge.headers(bridge, headers), options)

  @doc """
  Makes a GET request to a Hue bridge endpoint, raising on failure and extracting data.
  
  ## Parameters
  
  - `bridge` - Bridge configuration struct
  - `path` - API path on the bridge
  - `headers` - Additional headers (optional)
  - `options` - Request options (optional)
  
  ## Returns
  
  Response data on success, raises on failure.
  """
  @spec get_from_bridge!(%Hue.Conf.Bridge{}, String.t(), list(), keyword()) :: any()
  def get_from_bridge!(bridge, path, headers \\ [], options \\ []) do
    case get_from_bridge(bridge, path, headers, options) do
      response when response.success? -> Map.get(response.response, "data")
      _ -> raise "API error"
    end
  end

  @doc """
  Makes a PUT request to a Hue bridge endpoint.
  """
  @spec put_to_bridge(%Hue.Conf.Bridge{}, String.t(), any(), list(), keyword()) :: any()
  def put_to_bridge(bridge, path, data, headers \\ [], options \\ []),
    do: method_data(:put, bridge, path, data, headers, options)
  
  @doc """
  Makes a POST request to a Hue bridge endpoint.
  """
  @spec post_to_bridge(%Hue.Conf.Bridge{}, String.t(), any(), list(), keyword()) :: any()
  def post_to_bridge(bridge, path, data, headers \\ [], options \\ []),
    do: method_data(:post, bridge, path, data, headers, options)
  
  @doc """
  Makes a DELETE request to a Hue bridge endpoint.
  """
  @spec delete_to_bridge(%Hue.Conf.Bridge{}, String.t(), any(), list(), keyword()) :: any()
  def delete_to_bridge(bridge, path, _data, headers \\ [], options \\ []),
    do: method_data(:delete, bridge, path, headers, options)

  @doc """
  Makes an HTTP request with data to a Hue bridge endpoint.
  
  ## Parameters
  
  - `method` - HTTP method (atom or string)
  - `bridge` - Bridge configuration
  - `path` - API path
  - `data` - Request data
  - `headers` - Additional headers (optional)
  - `options` - Request options (optional)
  """
  @spec method_data(atom() | String.t(), %Hue.Conf.Bridge{}, String.t(), any(), list(), keyword()) :: any()
  def method_data(method, bridge, path, data, headers \\ [], options \\ [])
  
  def method_data(method, bridge, path, data, headers, options) when is_bitstring(method),
    do: method_data(String.to_atom(method), bridge, path, data, headers, options)
    
  def method_data(method, bridge, path, data, headers, options) when method in [:put, :post, :delete] do
    IO.inspect("Calling method #{method} on #{Bridge.url(bridge, path)} with data: #{inspect(data)}")
    call(method, Bridge.url(bridge, path), Bridge.headers(bridge, headers), data, options)
  end
  
  @doc """
  Makes an HTTP request with data to a Hue bridge endpoint, raising on failure.
  
  ## Parameters
  
  - `method` - HTTP method (atom or string)
  - `bridge` - Bridge configuration
  - `path` - API path
  - `data` - Request data
  - `headers` - Additional headers (optional)
  - `options` - Request options (optional)
  """
  @spec method_data!(atom() | String.t(), %Hue.Conf.Bridge{}, String.t(), any(), list(), keyword()) :: any()
  def method_data!(method, bridge, path, data, headers \\ [], options \\ [])
  
  def method_data!(method, bridge, path, data, headers, options) when is_bitstring(method),
    do: method_data!(String.to_atom(method), bridge, path, data, headers, options)
    
  def method_data!(method, bridge, path, data, headers, options) when method in [:put, :post, :delete] do
    case call(method, Bridge.url(bridge, path), Bridge.headers(bridge, headers), data, options) do
      nil -> raise "API error"
      response -> Map.get(response.response, data)
    end
  end
  
  defp http_options do
    [
      {:ssl, [
        {:verify, :verify_none},
        {:versions, [:"tlsv1.2", :"tlsv1.3"]}
      ]},
      {:timeout, 30_000},
      {:recv_timeout, 30_000}
    ]
  end

  defp get_header(header, key) do
    case Enum.find(header, &(elem(&1, 0) == key)) do
      {_key, val} -> val
      nil -> raise "can't find #{key}"
    end
  end
end
