defmodule Hue.Api.Resource do
  @moduledoc """
  Dynamic module generation for Hue API v2 resources.
  
  This module generates API client modules for all supported Hue resources based on 
  the official Hue API v2 specification. It creates:
  
  - A master Resource module with utility functions
  - Individual modules for each resource type (Light, Scene, Room, etc.)
  - GET, POST, PUT, DELETE methods as appropriate for each resource
  - Both base collection endpoints and individual resource endpoints
  - Rate limiting options for specific resource types
  
  ## Generated Modules
  
  Each resource generates a module like `Hue.Api.Light` with methods:
  - `get/1` - Get all resources of this type
  - `get/2` - Get specific resource by ID
  - `put/3` - Update specific resource
  - `post/2` - Create new resource (where supported)
  - `delete/2` - Delete resource (where supported)
  
  ## Reference
  
  See https://developers.meethue.com/develop/hue-api-v2/api-reference
  """
end

##
## see https://developers.meethue.com/develop/hue-api-v2/api-reference
##
resources_list  = [
  %{"light" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"scene" => %{"base" => ["post", "get"], "id" => ["delete", "put", "get"]}},
  %{"room" => %{"base" => ["post", "get"], "id" => ["delete", "put", "get"]}},
  %{"zone" => %{"base" => ["post", "get"], "id" => ["delete", "put", "get"]}},
  %{"bridge_home" => %{"base" => ["get"], "id" => ["get"]}},
  %{"grouped_light" => %{"base" => ["get"], "id" => ["put", "get"]}, "options" => [timestamp: [max_requests: 1]]},
  %{"device" => %{"base" => ["get"], "id" => ["delete", "put", "get"]}},
  %{"bridge" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"device_software_update" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"device_power" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"zigbee_connectivity" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"zgp_connectivity" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"zigbee_device_discovery" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"motion" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"service_group" =>  %{"base" => ["post", "get"], "id" => ["delete", "put", "get"]}},
  %{"grouped_motion" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"grouped_light_level" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"camera_motion" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"temperature" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"light_level" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"button" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"relative_rotary" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"behavior_script" => %{"base" => ["get"], "id" => ["get"]}},
  %{"behavior_instance" => %{"base" => ["post", "get"], "id" => ["delete", "put", "get"]}},
  %{"geofence_client" => %{"base" => ["post", "get"], "id" => ["delete", "put", "get"]}},
  %{"geolocation" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"entertainment_configuration" => %{"base" => ["post", "get"], "id" => ["delete", "put", "get"]}},
  %{"entertainment" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"homekit" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"matter" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"matter_fabric" => %{"base" => ["get"], "id" => ["delete", "get"]}},
  %{"smart_scene" => %{"base" => ["post", "get"], "id" => ["delete", "put", "get"]}},
  %{"contact" => %{"base" => ["get"], "id" => ["put", "get"]}},
  %{"tamper" => %{"base" => ["get"], "id" => ["put", "get"]}},
]

to_module_name = fn key ->
  ~r/_([a-z])/
  |> Regex.replace(String.capitalize(key), fn c -> String.upcase(c) end)
  |> String.replace("_", "")
end

resources_list_func =  quote do
  def resources_list do
    unquote(Enum.reduce(resources_list, [], fn resource, acc -> [resource |> Map.keys() |> List.first() | acc] end))
  end
end

resource_toresource_to_module_name = quote do
  @doc """
  Converts a resource name to its corresponding module name.
  
  ## Parameters
  
  - `key` - Resource name (e.g., "grouped_light")
  
  ## Returns
  
  Module name string (e.g., "GroupedLight").
  
  ## Examples
  
      resource_to_module_name("grouped_light") #=> "GroupedLight"
      resource_to_module_name("device_power") #=> "DevicePower"
  """
  @spec resource_to_module_name(String.t()) :: String.t()
  def resource_to_module_name(key)do
    ~r/_([a-z])/
    |> Regex.replace(String.capitalize(key), fn c -> String.upcase(c) end)
    |> String.replace("_", "")
  end
end

Module.create(Hue.Api.Resource, [resources_list_func, resource_to_module_name], Macro.Env.location(__ENV__))

for resource <- resources_list do
  key =
    resource
    |> Map.keys()
    |> List.first()
    
  module_name = to_module_name.(key)
  base_functions_list =
    resource
    |> Map.get(key)
    |> Map.get("base")
    |> Enum.map(fn
      method when method in ["get", "delete"] ->
        quote do
          def unquote(:"#{method}")(%Hue.Conf.Bridge{} = bridge) do
	    Hue.Api.get_from_bridge(bridge, unquote("/clip/v2/resource/#{key}"), [], unquote(Map.get(resource, "options", [])))
          end
          def unquote(:"#{method}!")(%Hue.Conf.Bridge{} = bridge) do
	    Hue.Api.get_from_bridge!(bridge, unquote("/clip/v2/resource/#{key}"), [], unquote(Map.get(resource, "options", [])))
          end
        end
    
      method ->
        quote do
          def unquote(:"#{method}")(%Hue.Conf.Bridge{} = bridge, data) do
	    Hue.Api.method_data(unquote(method), bridge, unquote("/clip/v2/resource/#{key}"), data, [], unquote(Map.get(resource, "options", [])))
          end
          def unquote(:"#{method}!")(%Hue.Conf.Bridge{} = bridge, data) do
	    Hue.Api.method_data!(unquote(method), bridge, unquote("/clip/v2/resource/#{key}"), data, [], unquote(Map.get(resource, "options", [])))
          end
        end
      end)

  id_functions_list =
    resource
    |> Map.get(key)
    |> Map.get("id")
    |> Enum.map(fn
      method when method in ["get", "delete"] ->
        quote do
          def unquote(:"#{method}")(%Hue.Conf.Bridge{} = bridge, id) do
	    Hue.Api.get_from_bridge(bridge, unquote("/clip/v2/resource/#{key}/") <> id, [], unquote(Map.get(resource, "options", [])))
          end
          def unquote(:"#{method}!")(%Hue.Conf.Bridge{} = bridge, id) do
	    Hue.Api.get_from_bridge!(bridge, unquote("/clip/v2/resource/#{key}/") <> id, [], unquote(Map.get(resource, "options", [])))
          end
        end
      
      method ->
	quote do
          def unquote(:"#{method}")(%Hue.Conf.Bridge{} = bridge, id, data) do
	    Hue.Api.method_data(unquote(method), bridge, unquote("/clip/v2/resource/#{key}/") <> id, data, [], unquote(Map.get(resource, "options", [])))
          end
          def unquote(:"#{method}!")(%Hue.Conf.Bridge{} = bridge, id, data) do
	    Hue.Api.method_data!(unquote(method), bridge, unquote("/clip/v2/resource/#{key}") <> id, data, [], unquote(Map.get(resource, "options", [])))
          end
        end
      end)
      
  Module.create(String.to_atom("Elixir.Hue.Api.#{module_name}"), base_functions_list ++ id_functions_list, Macro.Env.location(__ENV__))
end
