defmodule LocalizeWebTest do
  use ExUnit.Case
  doctest LocalizeWeb

  test "greets the world" do
    assert LocalizeWeb.hello() == :world
  end
end
