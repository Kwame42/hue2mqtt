import Config

config :hue_mqtt, :api,
  retry: 3

# SSL configuration for Hue bridge connections
config :ssl,
  protocol_version: [:"tlsv1.2", :"tlsv1.3"]

# HTTPoison configuration  
config :httpoison,
  timeout: 30_000,
  recv_timeout: 30_000

config_file = System.get_env("HUE_MQTT_CONFIG_FILE")
if config_file do
  config :hue_mqtt, :config_file, config_file
end
