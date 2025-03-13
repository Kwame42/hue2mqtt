defmodule Hue.Api do
  use GenServer
  use Log
  alias Hue.Conf.Bridge
  alias Hue.Api.Response
  alias Hue.Api.Response.Timestamp
  
  defstruct [bridges: %{}]
  
  @retries Application.compile_env!(:hue_mqtt, :api) |> Keyword.get(:retry) || 3

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
  
  def call(method, url, headers, data \\ nil, options \\ [])

  def call(method, url, headers, data, options) when is_nil(data) or is_bitstring(data),
    do: GenServer.call(Hue.Api, {:http, method, url, headers, data, options})

  def call(method, url, headers, data, options) when is_map(data),
    do: call(method, url, headers, Jason.encode!(data), options)
  
  def get_from_url(url, headers \\ [], options \\ []),
    do: call(:get, url, headers, nil,  options)

  def get_from_url!(url, headers \\ [], options \\ []) do
    case get_from_url(url, headers, options) do
      {:ok, data} -> data
      _ -> raise "API error"
    end
  end

  def get_from_bridge(bridge, path, headers \\ [], options \\ []),
    do: get_from_url(Bridge.url(bridge, path), Bridge.headers(bridge, headers), options)

  def get_from_bridge!(bridge, path, headers \\ [], options \\ []) do
    case get_from_bridge(bridge, path, headers, options) do
      response when response.success? -> Map.get(response.response, "data")
      _ -> raise "API error"
    end
  end

  def put_to_bridge(bridge, path, data, headers \\ [], options \\ []),
    do: method_data(:put, bridge, path, data, headers, options)
  
  def post_to_bridge(bridge, path, data, headers \\ [], options \\ []),
    do: method_data(:post, bridge, path, data, headers, options)
  
  def delete_to_bridge(bridge, path, _data, headers \\ [], options \\ []),
    do: method_data(:delete, bridge, path, headers, options)

  def method_data(method, bridge, path, data, headers \\ [], options \\ [])
  
  def method_data(method, bridge, path, data, headers, options) when is_bitstring(method),
    do: method_data(String.to_atom(method), bridge, path, data, headers, options)
    
  def method_data(method, bridge, path, data, headers, options) when method in [:put, :post, :delete],
    do: call(method, Bridge.url(bridge, path), Bridge.headers(bridge, headers), data, options)
  
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
    [{:ssl, [{:verify, :verify_none}]}]
  end

  defp get_header(header, key) do
    case Enum.find(header, &(elem(&1, 0) == key)) do
      {_key, val} -> val
      nil -> raise "can't find #{key}"
    end
  end
end
