defmodule Log do
  @moduledoc """
  Logging utility module that provides a macro for adding standardized logging functionality to other modules.
  
  When used via `use Log`, this module injects logging functions (info/1, warning/1, error/1) 
  that prefix log messages with the calling module name for better traceability.
  
  ## Usage
  
      defmodule MyModule do
        use Log
        
        def some_function do
          info("This is an info message")
          warning("This is a warning")
          error("This is an error")
        end
      end
  """
  
  require Logger

  defmacro __using__(_opts) do
    quote do
      require Logger
      
      @doc """
      Internal logging helper that formats messages with module name prefix.
      """
      @spec do_logger(module(), any(), (String.t() -> :ok)) :: :ok
      def do_logger(name, data, log) do
	"[#{name}] "
	|> Kernel.<>(inspect(data))
	|> log.()
      end

      @doc """
      Logs an info message with module name prefix.
      """
      @spec info(any()) :: :ok
      def info(data), do: do_logger(__MODULE__, data, &Logger.info/1)
      
      @doc """
      Logs a warning message with module name prefix.
      """
      @spec warning(any()) :: :ok
      def warning(data), do: do_logger(__MODULE__, data, &Logger.warning/1)
      
      @doc """
      Logs an error message with module name prefix.
      """
      @spec error(any()) :: :ok
      def error(data), 	do: do_logger(__MODULE__, data, &Logger.error/1)
    end
  end
end
