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
  Gets all cookies from a cookie jar.
  """
  @spec get_cookies(t()) :: cookies()
  def get_cookies(cookie_jar) do
    GenServer.call(cookie_jar, :get_cookies)
  end

  @doc """
  Creates a Cookie header field.
  If there's nothing to send, returns an empty string.
  """
  @spec create_header(t(), URI.t()) :: binary()
  def create_header(cookie_jar, request_uri) do
    GenServer.call(cookie_jar, {:create_header, request_uri})
  end

  @doc """
  Process a Set-Cookie header field.
  """
  @spec process_header(t(), URI.t(), String.t()) :: :ok
  def process_header(cookie_jar, request_uri, header) do
    GenServer.cast(cookie_jar, {:process_header, request_uri, header})
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

  @impl true
  @spec handle_call({:create_header, URI.t()}, GenServer.from(), cookies()) ::
          {:reply, binary(), cookies()}
  def handle_call({:create_header, _request_uri}, _from, cookies) do
    list =
      cookies
      |> Map.to_list()

    header =
      list
      |> Enum.map_join("; ", fn {k, v} -> k.name <> "=" <> v.value end)

    {:reply, header, cookies}
  end

  @impl true
  def handle_cast({:process_header, _request_uri, _header}, cookies) do
    {:noreply, cookies}
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
