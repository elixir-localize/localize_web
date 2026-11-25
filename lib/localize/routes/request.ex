defmodule Localize.Routes.Request do
  @moduledoc """
  The parts of a request that the functions given to `Localize.Plug.LocalePrefix` and `Localize.Live.LocalePrefix` are called with.

  A function that finds a site's URL mode, default locale or supported locales, or tests whether a page exists, is called on an HTTP request by the plug and on a live navigation by the hook. A live navigation has no `conn`, so both call it with this struct, and a function that finds a site from the host, or from an assign set by the application's own plug or `on_mount` hook, finds it the same way in both.

  * `:host` is the request's host, such as `"example.com"`.

  * `:path` is the requested path, without the script name of a mounted application or the query string.

  * `:session` is the session: the `conn`'s, when it has been fetched, or the LiveView's.

  * `:assigns` is the `conn`'s assigns or the socket's.

  """

  defstruct host: nil, path: "/", session: %{}, assigns: %{}

  @typedoc "A request, as the module documentation describes it."
  @type t :: %__MODULE__{
          host: String.t() | nil,
          path: String.t(),
          session: map(),
          assigns: map()
        }

  @doc """
  Returns the request of a `conn`.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * A `t:t/0`.

  ### Examples

      iex> conn = Plug.Test.conn(:get, "http://example.com/fr/about?page=2")
      iex> Localize.Routes.Request.from_conn(conn)
      %Localize.Routes.Request{host: "example.com", path: "/fr/about", session: %{}, assigns: %{}}

  """
  @spec from_conn(Plug.Conn.t()) :: t()
  def from_conn(%Plug.Conn{} = conn) do
    %__MODULE__{
      host: conn.host,
      path: "/" <> Enum.join(conn.path_info, "/"),
      session: Map.get(conn.private, :plug_session, %{}),
      assigns: conn.assigns
    }
  end
end
