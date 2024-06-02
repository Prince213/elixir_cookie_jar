defmodule CookieJar do
  @moduledoc """
  A cookie jar.

  ## References

    * [RFC 6265](https://datatracker.ietf.org/doc/html/rfc6265)
  """
  use GenServer

  @type t() :: pid()

  @type cookies() :: %{
          %{
            name: String.t()
          } => %{
            value: String.t()
          }
        }

  @impl true
  def init(cookies) do
    {:ok, cookies}
  end

  @doc """
  Hello world.

  ## Examples

      iex> CookieJar.hello()
      :world

  """
  def hello do
    :world
  end
end
