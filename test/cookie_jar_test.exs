defmodule CookieJarTest do
  use ExUnit.Case
  doctest CookieJar

  test "greets the world" do
    assert CookieJar.hello() == :world
  end
end
