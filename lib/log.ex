defmodule Log do
  require Logger

  defmacro __using__(_opts) do
    quote do
      require Logger
      
      def do_logger(name, data, log) do
	"[#{name}] "
	|> Kernel.<>(inspect(data))
	|> log.()
      end

      def info(data), do: do_logger(__MODULE__, data, &Logger.info/1)
      def warning(data), do: do_logger(__MODULE__, data, &Logger.warning/1)
      def error(data), 	do: do_logger(__MODULE__, data, &Logger.error/1)
    end
  end
end
