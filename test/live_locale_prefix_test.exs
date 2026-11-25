defmodule Localize.LiveLocalePrefixTest.Sites do
  def url_mode(%Localize.Routes.Request{host: "all.example"}) do
    :prefix_all
  end

  def url_mode(%Localize.Routes.Request{}) do
    :prefix_others
  end

  def published?(%Localize.Routes.Request{}, rest, locale) do
    rest != "/news" or locale.cldr_locale_id == :en
  end
end

defmodule Localize.LiveLocalePrefixTest.PageLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    {:noreply,
     assign(socket,
       uri: uri,
       locale: Localize.get_locale().cldr_locale_id,
       gettext: Gettext.get_locale(MyApp.Gettext),
       contact: Localize.Routes.Prefix.localized_path(socket, "/contact"),
       supported: Enum.join(Localize.Live.LocalePrefix.get_settings(socket).supported, " ")
     )}
  end

  def handle_event("patch", %{"to" => to}, socket) do
    {:noreply, push_patch(socket, to: to)}
  end

  def render(assigns) do
    ~H"""
    <p id="locale">{@locale}</p>
    <p id="gettext">{@gettext}</p>
    <p id="contact">{@contact}</p>
    <p id="supported">{@supported}</p>
    <p id="uri">{@uri}</p>
    """
  end
end

defmodule Localize.LiveLocalePrefixTest.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import Localize.Routes, only: [locale_prefix: 1]

  alias Localize.LiveLocalePrefixTest.{PageLive, Sites}

  pipeline :browser do
    plug(:fetch_session)

    plug(Localize.Plug.PutLocale,
      from: [:path_prefix, :session, :accept_language],
      supported: ["en", "fr", "de"],
      default: "en"
    )

    plug(Localize.Plug.LocalePrefix,
      mode: {Sites, :url_mode},
      exists?: {Sites, :published?}
    )
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default,
      on_mount: [{Localize.Live.LocalePrefix, gettext: MyApp.Gettext}],
      session: {Localize.Live.LocalePrefix, :session, []} do
      locale_prefix do
        live("/about", PageLive, :about)
        live("/news", PageLive, :news)
        live("/contact", PageLive, :contact)
      end
    end
  end
end

defmodule Localize.LiveLocalePrefixTest.Endpoint do
  use Phoenix.Endpoint, otp_app: :localize_web

  @session_options [store: :cookie, key: "_live_prefix", signing_salt: "prefix"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])
  plug(Plug.Session, @session_options)
  plug(Localize.LiveLocalePrefixTest.Router)
end

defmodule Localize.LiveLocalePrefixTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  alias Localize.LiveLocalePrefixTest.Endpoint

  doctest Localize.Live.LocalePrefix

  @endpoint Endpoint

  setup_all do
    Application.put_env(:localize_web, Endpoint,
      secret_key_base: String.duplicate("live-locale-prefix-secret-", 3),
      live_view: [signing_salt: "live_prefix_lv"]
    )

    {:ok, _pid} = Endpoint.start_link()
    :ok
  end

  defp text(html, id) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("##{id}")
    |> LazyHTML.text()
  end

  defp prefix_all_conn do
    %{build_conn() | host: "all.example"}
  end

  describe "on mount" do
    test "takes the locale and settings the plugs resolved for the page" do
      {:ok, _view, html} = live(build_conn(), "/fr/about")

      assert text(html, "locale") == "fr"
      assert text(html, "gettext") == "fr"
      assert text(html, "contact") == "/fr/contact"
      assert text(html, "supported") == "en fr de"
    end

    test "serves an unprefixed address in the default locale under :prefix_others" do
      conn = Plug.Test.init_test_session(build_conn(), %{"localize_locale" => "fr"})
      {:ok, _view, html} = live(conn, "/about")

      assert text(html, "locale") == "en"
      assert text(html, "contact") == "/contact"
    end
  end

  describe "on a navigation" do
    test "sets the locale a prefixed address names" do
      {:ok, view, _html} = live(build_conn(), "/fr/about")

      html = render_hook(view, "patch", %{"to" => "/de/about?page=2"})
      assert text(html, "locale") == "de"
      assert text(html, "gettext") == "de"
      assert text(html, "contact") == "/de/contact"
    end

    test "redirects the default locale's prefix under :prefix_others, keeping the query string" do
      {:ok, view, _html} = live(build_conn(), "/fr/about")

      render_hook(view, "patch", %{"to" => "/en/about?page=2"})
      assert_redirect(view, "/about?page=2")
    end

    test "sets the default locale for an unprefixed address under :prefix_others" do
      {:ok, view, _html} = live(build_conn(), "/fr/about")

      html = render_hook(view, "patch", %{"to" => "/about"})
      assert text(html, "locale") == "en"
    end

    test "redirects an unprefixed address to the current locale under :prefix_all" do
      {:ok, view, _html} = live(prefix_all_conn(), "/fr/about")

      render_hook(view, "patch", %{"to" => "/contact"})
      assert_redirect(view, "/fr/contact")
    end

    test "redirects to the default locale when :exists? says the page is not in the current one" do
      {:ok, view, _html} = live(prefix_all_conn(), "/fr/about")

      render_hook(view, "patch", %{"to" => "/news"})
      assert_redirect(view, "/en/news")
    end

    test "ends the LiveView for a locale parameter naming no supported locale" do
      Process.flag(:trap_exit, true)
      {:ok, view, _html} = live(build_conn(), "/fr/about")

      capture_log(fn ->
        catch_exit(render_hook(view, "patch", %{"to" => "/blog/about"}))
      end)

      assert_receive {:EXIT, _pid,
                      {%Localize.Plug.LocalePrefix.NotFoundError{locale: "blog"}, _stacktrace}}
    end

    test "does not read a locale query parameter as the route's" do
      {:ok, view, _html} = live(build_conn(), "/fr/about")

      html = render_hook(view, "patch", %{"to" => "/fr/about?locale=blog"})
      assert text(html, "locale") == "fr"
    end
  end

  describe "parity with the plug" do
    test "an HTTP request and a navigation to the same address make the same decision" do
      for {conn_fun, from, to, expected} <- [
            {&build_conn/0, "/fr/about", "/en/about", {:redirect, "/about"}},
            {&build_conn/0, "/fr/about", "/de/about", {:locale, "de"}},
            {&prefix_all_conn/0, "/fr/about", "/news", {:redirect, "/en/news"}}
          ] do
        http = get(Plug.Test.init_test_session(conn_fun.(), %{"localize_locale" => "fr"}), to)
        {:ok, view, _html} = live(conn_fun.(), from)

        case expected do
          {:redirect, location} ->
            assert redirected_to(http, http.status) == location
            render_hook(view, "patch", %{"to" => to})
            assert_redirect(view, location)

          {:locale, locale} ->
            assert http.status == 200
            assert text(render_hook(view, "patch", %{"to" => to}), "locale") == locale
        end
      end
    end
  end

  describe "session/1" do
    test "hands the LiveView the locale and the resolved settings" do
      conn =
        build_conn()
        |> Map.put(:host, "all.example")
        |> get("/fr/about")

      assert %{
               "localize_locale" => "fr",
               "localize_locale_prefix" => %{
                 "mode" => :prefix_all,
                 "default" => "en",
                 "supported" => ["en", "fr", "de"],
                 "param" => "locale",
                 "exists?" => {Localize.LiveLocalePrefixTest.Sites, :published?}
               }
             } = Localize.Live.LocalePrefix.session(conn)
    end
  end

  describe "without settings in the session" do
    test "logs and leaves navigations unchecked" do
      socket = %Phoenix.LiveView.Socket{}

      log =
        capture_log(fn ->
          assert {:cont, %Phoenix.LiveView.Socket{}} =
                   Localize.Live.LocalePrefix.on_mount(:default, %{}, %{}, socket)
        end)

      assert log =~ "the session holds no settings"
    end
  end
end
