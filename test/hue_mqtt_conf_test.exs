defmodule HueMqttTest.Hue.Conf do
  use ExUnit.Case, async: true
  import Hue.Conf
  doctest Hue.Conf
  
  defp bridge(attrs \\ %{}) do
    %Hue.Conf.Bridge{
      id: "123456",
      ip: "1.1.1.1"
    }
    |> Map.merge(attrs)
  end
  
  setup do
    start_supervised(Hue.Conf)
    :ok
  end

  test "application starts with an empty list of bridges" do
     assert list() == %Hue.Conf{bridges_list: %{}}
     assert update(bridge()) == %Hue.Conf{bridges_list: %{bridge().id => bridge()}}
     assert update(bridge(%{login: "test"})) == %Hue.Conf{bridges_list: %{bridge().id => bridge(%{login: "test"})}}
     assert get(bridge().id) == bridge(%{login: "test"})
  end
end
