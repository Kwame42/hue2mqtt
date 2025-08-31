FROM elixir
RUN mkdir /app
WORKDIR /app
COPY . hue_mqtt
WORKDIR /app/hue_mqtt
RUN mix deps.get
RUN mix compile
VOLUME ["/data"]
CMD ["mix", "hue.mqtt.server"]