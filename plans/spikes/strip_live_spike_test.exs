# SPIKE, not a test of the library: does a locale prefix stripped before the
# router survive a LiveView connect, push_patch and live navigation, and does
# declaring each live route twice (plain and under "/:locale") instead work?
# See plans/runtime-locale-routing.md, "Open questions".

defmodule Spike.Live do
  use Phoenix.LiveView

  def mount(params, _session, socket) do
    {:ok, assign(socket, locale: params["locale"] || "en", uri: nil, params: %{})}
  end

  def handle_params(params, uri, socket) do
    {:noreply,
     assign(socket, uri: uri, params: params, locale: params["locale"] || socket.assigns.locale)}
  end

  def handle_event("patch", %{"to" => to}, socket), do: {:noreply, push_patch(socket, to: to)}

  def handle_event("navigate", %{"to" => to}, socket),
    do: {:noreply, push_navigate(socket, to: to)}

  def render(assigns) do
    ~H"""
    <p id="locale">{@locale}</p>
    <p id="uri">{@uri}</p>
    """
  end
end

# A strips "/fr" or "/de" from path_info before the router.
defmodule Spike.StripPrefix do
  @behaviour Plug
  def init(options), do: options

  def call(%Plug.Conn{path_info: [segment | rest]} = conn, _options)
      when segment in ["fr", "de"] do
    conn
    |> Plug.Conn.put_private(:spike_locale, segment)
    |> Map.put(:path_info, rest)
  end

  def call(conn, _options), do: conn
end

defmodule Spike.RouterA do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default do
      live("/about", Spike.Live)
      live("/other", Spike.Live)
    end
  end
end

# B declares each live route twice, plain and under "/:locale".
defmodule Spike.RouterB do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default do
      live("/about", Spike.Live)
      live("/other", Spike.Live)

      scope "/:locale" do
        live("/about", Spike.Live)
        live("/other", Spike.Live)
      end
    end
  end
end

defmodule Spike.EndpointA do
  use Phoenix.Endpoint, otp_app: :localize_web
  @session_options [store: :cookie, key: "_spike", signing_salt: "spike"]
  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])
  plug(Plug.Session, @session_options)
  plug(Spike.StripPrefix)
  plug(Spike.RouterA)
end

defmodule Spike.EndpointB do
  use Phoenix.Endpoint, otp_app: :localize_web
  @session_options [store: :cookie, key: "_spike", signing_salt: "spike"]
  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])
  plug(Plug.Session, @session_options)
  plug(Spike.RouterB)
end

defmodule Spike.StripLiveSpikeTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  @config [
    secret_key_base: String.duplicate("spike-secret-key-base-", 4),
    live_view: [signing_salt: "spike_lv"]
  ]

  setup_all do
    for endpoint <- [Spike.EndpointA, Spike.EndpointB] do
      Application.put_env(:localize_web, endpoint, @config)
      {:ok, _pid} = endpoint.start_link()
    end

    :ok
  end

  defp text(html, id),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query("##{id}") |> LazyHTML.text()

  describe "A: prefix stripped before the router" do
    @endpoint Spike.EndpointA

    test "A1 dead render of /fr/about" do
      conn = get(build_conn(), "/fr/about")
      IO.puts("\nA1 dead render /fr/about: status #{conn.status}")
    end

    test "A2 connected mount of /fr/about" do
      result =
        try do
          capture_log(fn -> send(self(), {:r, live(build_conn(), "/fr/about")}) end)
          receive do: ({:r, r} -> r)
        rescue
          e -> {:raised, Exception.message(e) |> String.slice(0, 160)}
        catch
          kind, value -> {kind, inspect(value) |> String.slice(0, 160)}
        end

      IO.puts("\nA2 live /fr/about: #{inspect(result, limit: :infinity) |> String.slice(0, 300)}")
    end

    test "A3 from /about, navigate to /fr/other and patch to /fr/about" do
      {:ok, view, _html} = live(build_conn(), "/about")

      navigate =
        try do
          render_hook(view, "navigate", %{"to" => "/fr/other"})
          {:navigated, assert_redirect(view, 100)}
        rescue
          e -> {:raised, Exception.message(e) |> String.slice(0, 160)}
        catch
          kind, value -> {kind, inspect(value) |> String.slice(0, 160)}
        end

      IO.puts("\nA3 push_navigate /fr/other: #{inspect(navigate) |> String.slice(0, 260)}")

      {:ok, view, _html} = live(build_conn(), "/about")

      patch =
        try do
          capture_log(fn ->
            send(self(), {:r, render_hook(view, "patch", %{"to" => "/fr/about"})})
          end)

          receive do: ({:r, r} -> {:patched, String.slice(r, 0, 80)})
        catch
          kind, value -> {kind, inspect(value) |> String.slice(0, 200)}
        end

      IO.puts("A3 push_patch /fr/about: #{inspect(patch) |> String.slice(0, 260)}")
    end
  end

  describe "B: each live route declared plain and under /:locale" do
    @endpoint Spike.EndpointB

    test "B1 connected mount of /fr/about and of /about" do
      {:ok, _view, html} = live(build_conn(), "/fr/about")
      IO.puts("\nB1 live /fr/about: locale=#{text(html, "locale")}")

      {:ok, _view, html} = live(build_conn(), "/about")
      IO.puts("B1 live /about: locale=#{text(html, "locale")}")
    end

    test "B2 patch within a language and navigate between languages" do
      {:ok, view, _html} = live(build_conn(), "/fr/about")

      html = render_hook(view, "patch", %{"to" => "/fr/about?page=2"})
      IO.puts("\nB2 push_patch /fr/about?page=2: uri=#{text(html, "uri")}")

      render_hook(view, "navigate", %{"to" => "/de/other"})
      {to, _flash} = assert_redirect(view)
      IO.puts("B2 push_navigate /de/other: live redirect to #{to}")
      {:ok, _view, html} = live(build_conn(), to)
      IO.puts("B2 after navigate: locale=#{text(html, "locale")}")

      {:ok, view, _html} = live(build_conn(), "/fr/about")
      render_hook(view, "navigate", %{"to" => "/about"})
      {to, _flash} = assert_redirect(view)
      IO.puts("B2 push_navigate /fr/about -> /about: live redirect to #{to}")
    end

    test "B5 navigation type of a prefixed path, seen from a mounted view" do
      {:ok, view, _html} = live(build_conn(), "/fr/about")
      render_hook(view, "navigate", %{"to" => "/de/other"})
      assert_redirect(view, "/de/other")
      IO.puts("\nB5 same live session, so /de/other is a live navigation (not an href)")
    end

    test "B3 a bogus first segment is captured as :locale" do
      info = Phoenix.Router.route_info(Spike.RouterB, "GET", "/blog/about", "")
      IO.puts("\nB3 /blog/about matches: #{inspect(info[:path_params])}")
    end

    test "B4 verified routes accept both forms" do
      {_result, warnings} =
        Code.with_diagnostics(fn ->
          Code.compile_string("""
          defmodule Spike.Verified do
            use Phoenix.VerifiedRoutes, router: Spike.RouterB, endpoint: Spike.EndpointB
            def plain, do: ~p"/about"
            def localized(locale), do: ~p"/\#{locale}/about"
            def missing, do: ~p"/nowhere"
          end
          """)
        end)

      IO.puts("\nB4 verified route warnings: #{inspect(Enum.map(warnings, & &1.message))}")
      IO.puts("B4 localized(\"fr\") = #{apply(Spike.Verified, :localized, ["fr"])}")
    end
  end
end
