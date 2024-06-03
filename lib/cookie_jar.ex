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

  @doc """
  Creates a cookie jar linked to the current process.
  """
  @spec start_link(cookies()) :: GenServer.on_start()
  def start_link(cookies \\ %{}) do
    GenServer.start_link(__MODULE__, cookies)
  end

  @doc """
  Get all cookies from a cookie jar.
  """
  @spec get_cookies(t()) :: cookies()
  def get_cookies(cookie_jar) do
    GenServer.call(cookie_jar, :get_cookies)
  end

  def create_header(cookie_jar, uri) do
    GenServer.call(cookie_jar, {:create_header, uri})
  end

  @impl true
  @spec init(cookies()) :: {:ok, cookies()}
  def init(cookies) do
    {:ok, cookies}
  end

  @impl true
  @spec handle_call(:get_cookies, GenServer.from(), cookies()) ::
          {:reply, cookies(), cookies()}
  def handle_call(:get_cookies, _from, cookies) do
    {:reply, cookies, cookies}
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
