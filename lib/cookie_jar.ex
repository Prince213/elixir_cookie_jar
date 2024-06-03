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
            name: String.t(),
            path: String.t()
          } => %{
            value: String.t(),
            expiry_time: DateTime.t(),
            creation_time: DateTime.t(),
            last_access_time: DateTime.t(),
            persistent: boolean(),
            secure_only: boolean(),
            http_only: boolean()
          }
        }

  @type cookie() :: %{
          uri: URI.t(),
          name: String.t(),
          value: String.t(),
          attrs: [
            {:expires, DateTime.t()}
            | {:max_age, DateTime.t()}
            | {:path, String.t()}
            | {:secure, true}
            | {:http_only, true}
          ]
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
  def handle_call({:create_header, request_uri}, _from, cookies) do
    now = DateTime.utc_now()

    {cookies, list} =
      cookies
      |> Map.to_list()
      |> Enum.filter(fn {_, x} ->
        DateTime.compare(now, x.expiry_time) == :lt
      end)
      |> Enum.map_reduce([], fn {k, v}, acc ->
        with true <- path_matches?(request_uri.path, k.path),
             true <- not v.secure_only or request_uri.scheme == "https",
             true <-
               not v.http_only or
                 Enum.member?(~w(http https), request_uri.scheme),
             now <- DateTime.utc_now() do
          v = %{v | last_access_time: now}
          {{k, v}, [{k, v}] ++ acc}
        else
          _ -> {{k, v}, acc}
        end
      end)

    cookies = Map.new(cookies)

    header =
      list
      |> Enum.sort(fn {k1, v1}, {k2, v2} ->
        if byte_size(k1.path) != byte_size(k2.path) do
          byte_size(k1.path) < byte_size(k2.path)
        else
          DateTime.compare(v1.creation_time, v2.creation_time) == :lt
        end
      end)
      |> Enum.map_join("; ", fn {k, v} -> k.name <> "=" <> v.value end)

    {:reply, header, cookies}
  end

  @impl true
  @spec handle_cast({:process_header, URI.t(), String.t()}, cookies()) ::
          {:noreply, cookies()}
  def handle_cast({:process_header, request_uri, header}, cookies) do
    cookie = parse_header(request_uri, header)

    {:noreply,
     cookies
     |> store_cookie(cookie)}
  end

  @spec parse_header(URI.t(), String.t()) :: cookie() | nil
  defp parse_header(request_uri, header) do
    with [pair | attrs] <- String.split(header, ";"),
         [name | value] <- String.split(pair, "=", parts: 2),
         true <- value != [],
         value <- List.first(value) |> trim_wsp(),
         name <- trim_wsp(name),
         true <- name != "" do
      attrs =
        attrs
        |> Enum.map(fn attr ->
          with [name | value] <- String.split(attr, "=", parts: 2),
               name <- name |> trim_wsp() |> String.downcase(),
               value <- List.first(value, "") |> trim_wsp() do
            case name do
              "expires" ->
                time = parse_expires(value)
                if time, do: {:expires, time}

              "max-age" ->
                with true <- value =~ ~r/^[\-\d]\d*$/,
                     delta <- String.to_integer(value) do
                  {:max_age,
                   if delta <= 0 do
                     DateTime.from_unix!(0)
                   else
                     DateTime.utc_now() |> DateTime.add(delta)
                   end}
                else
                  _ -> nil
                end

              "path" ->
                {:path,
                 if value == "" or :binary.first(value) != ?/ do
                   default_path(request_uri)
                 else
                   value
                 end}

              "secure" ->
                {:secure, true}

              "httponly" ->
                {:http_only, true}

              _ ->
                nil
            end
          end
        end)
        |> Enum.filter(&(not is_nil(&1)))

      %{
        uri: request_uri,
        name: name,
        value: value,
        attrs: attrs
      }
    else
      _ -> nil
    end
  end

  @spec store_cookie(cookies(), cookie() | nil) :: cookies()
  defp store_cookie(cookies, cookie) do
    with false <- is_nil(cookie) do
      cookie =
        Enum.reduce(
          cookie.attrs,
          %{
            uri: cookie.uri,
            name: cookie.name,
            value: cookie.value,
            expires: nil,
            max_age: nil,
            path: default_path(cookie.uri),
            secure: false,
            http_only: false
          },
          fn {k, v}, acc -> Map.put(acc, k, v) end
        )
        |> (fn c ->
              cond do
                not is_nil(c.max_age) ->
                  c
                  |> Map.put(:persistent, true)
                  |> Map.put(:expiry_time, c.max_age)

                not is_nil(c.expires) ->
                  c
                  |> Map.put(:persistent, true)
                  |> Map.put(:expiry_time, c.expires)

                true ->
                  c
                  |> Map.put(:persistent, false)
                  |> Map.put(:expiry_time, ~U[2099-12-31 23:59:59Z])
              end
            end).()

      if cookie do
        cookie =
          {%{
             name: cookie.name,
             path: cookie.path
           },
           %{
             value: cookie.value,
             expiry_time: cookie.expiry_time,
             creation_time: DateTime.utc_now(),
             last_access_time: DateTime.utc_now(),
             persistent: cookie.persistent,
             secure_only: cookie.secure,
             http_only: cookie.http_only
           }}

        old = Map.get(cookies, elem(cookie, 0))

        cookie =
          if old do
            {
              elem(cookie, 0),
              elem(cookie, 1) |> Map.put(:creation_time, old.creation_time)
            }
          else
            cookie
          end

        cookies
        |> Map.put(elem(cookie, 0), elem(cookie, 1))
      else
        cookies
      end
    else
      _ -> cookies
    end
  end

  defp parse_expires(_value) do
    nil
  end

  # https://datatracker.ietf.org/doc/html/rfc6265#section-5.1.4
  @spec default_path(URI.t()) :: binary()
  defp default_path(uri) do
    with path <- uri.path || "",
         false <- path == "" or :binary.first(path) != ?/,
         bytes <- :binary.bin_to_list(path),
         false <- Enum.count(bytes, &(&1 == ?/)) <= 1 do
      length =
        bytes
        |> Enum.reverse()
        |> Enum.find_index(&(&1 == ?/))

      length = byte_size(path) - (1 + length)

      binary_slice(path, 0, length)
    else
      _ -> "/"
    end
  end

  # https://datatracker.ietf.org/doc/html/rfc6265#section-5.1.4
  @spec path_matches?(String.t(), String.t()) :: boolean()
  defp path_matches?(request_path, cookie_path) do
    cond do
      cookie_path == request_path ->
        true

      not String.starts_with?(request_path, cookie_path) ->
        false

      :binary.last(cookie_path) == ?/ ->
        true

      :binary.at(request_path, byte_size(cookie_path)) == ?/ ->
        true

      true ->
        false
    end
  end

  @spec trim_wsp(String.t()) :: String.t()
  defp trim_wsp(string) do
    string
    |> (&Regex.replace(~r/^[ \t]*/, &1, "")).()
    |> (&Regex.replace(~r/[ \t]*$/, &1, "")).()
  end
end
