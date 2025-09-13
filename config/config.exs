import Config

config :hue_mqtt, :api,
  retry: 3

config_file = System.get_env("HUE_MQTT_CONFIG_FILE")
if config_file do
  config :hue_mqtt, :config_file, config_file
end
