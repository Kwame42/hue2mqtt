defmodule Mqtt.Handler do
  @moduledoc """
  Tortoise.Handler implementation for processing MQTT messages.
  """
  
  use Tortoise.Handler
  use Log

  @impl Tortoise.Handler
  def init(args) do
    info("MQTT handler initialized")
    {:ok, args}
  end

  @impl Tortoise.Handler
  def connection(status, state) do
    info("MQTT connection status: #{inspect(status)}")
    
    case status do
      :up ->
        # Publish online status when connected
        Tortoise.publish("hue2mqtt", "hue2mqtt/status", "online", qos: 1, retain: true)
      :down ->
        warning("MQTT connection lost")
    end
    
    {:ok, state}
  end

  @impl Tortoise.Handler
  def handle_message(topic, payload, state) do
    info("Received MQTT message on topic: #{topic}")
    
    topic
    |> Mqtt.topic_to_hue()
    |> hue_bridge(payload)
    
    {:ok, state}
  end

  @impl Tortoise.Handler
  def terminate(reason, _state) do
    info("MQTT handler terminating: #{inspect(reason)}")
    # Publish offline status when terminating
    Tortoise.publish("hue2mqtt", "hue2mqtt/status", "offline", qos: 1, retain: true)
    :ok
  end

  # Private function to handle Hue bridge communication
  defp hue_bridge(%Mqtt{} = hue, _payload) when hue.valid? == false,
    do: error("Mqtt HUE error [#{hue.bridge_id}, #{hue.module}, #{hue.method}]: #{hue.error |> Enum.intersperse("\n") |> List.to_string()}")

  defp hue_bridge(%Mqtt{method: :set} = hue, payload) do
    info("Set HUE bridge resource: [#{hue.bridge.ip}/#{hue.module}/#{hue.resource_id}] (#{hue.module}) with payload #{inspect payload}")
    with {:ok, encoded_payload} <- Jason.decode(payload),
         %Hue.Api.Response{} = response when response.success? <- apply(:"Elixir.Hue.Api.#{hue.module}", :put, [hue.bridge, hue.resource_id, encoded_payload]) do
      info(response)
      new_payload = Map.put(encoded_payload, :hue2mqtt, %{service: "hue2mqtt"})
      Mqtt.publish_to_mqtt("#{hue.resource}/#{hue.resource_id}", new_payload)
      |> info()
    else
      _ -> error("Payload: #{inspect(payload)} invalid, must be JSON type")
    end
  end

  defp hue_bridge(%Mqtt{} = hue, _payload) do
    info("MQTT HUE info [#{hue.module}, #{hue.resource_id}]") 
  end
  
  defp hue_bridge(data, _) do
    info("I don't handle this... #{inspect(data)}")
  end
end
