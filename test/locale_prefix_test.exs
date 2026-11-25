defmodule Localize.LocalePrefixTest.PageLive do
  use Phoenix.LiveView

  def mount(params, _session, socket) do
    {:ok, assign(socket, locale: params["locale"] || "none", uri: nil)}
  end

  def handle_params(params, uri, socket) do
    {:noreply, assign(socket, uri: uri, locale: params["locale"] || "none")}
  end

  def handle_event("patch", %{"to" => to}, socket) do
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("navigate", %{"to" => to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  def render(assigns) do
    ~H"""
    <p id="locale">{@locale}</p>
    <p id="uri">{@uri}</p>
    """
  end
end

defmodule Localize.LocalePrefixTest.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import Localize.Routes, only: [locale_prefix: 1, locale_prefix: 2]

  alias Localize.LocalePrefixTest.PageLive

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default do
      locale_prefix do
        live("/", PageLive, :home)
        live("/about", PageLive, :about)
        live("/products/:id", PageLive, :product)

        scope "/admin" do
          live("/:section", PageLive, :admin)
        end
      end
    end
  end
end

defmodule Localize.LocalePrefixTest.HelpersRouter do
  use Phoenix.Router, helpers: true
  use Localize.Routes, gettext: MyApp.Gettext, helpers: true

  locale_prefix param: "lang" do
    get("/pages/:page", PageController, :show)
  end
end

defmodule Localize.LocalePrefixTest.Endpoint do
  use Phoenix.Endpoint, otp_app: :localize_web

  @session_options [store: :cookie, key: "_locale_prefix", signing_salt: "prefix"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])
  plug(Plug.Session, @session_options)
  plug(Localize.LocalePrefixTest.Router)
end

defmodule Localize.LocalePrefixTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Localize.LocalePrefixTest.{Endpoint, HelpersRouter, Router}

  @endpoint Endpoint

  setup_all do
    Application.put_env(:localize_web, Endpoint,
      secret_key_base: String.duplicate("locale-prefix-secret-", 4),
      live_view: [signing_salt: "locale_prefix_lv"]
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

  defp match(router, path) do
    case Phoenix.Router.route_info(router, "GET", path, "") do
      :error -> :error
      info -> {info.route, info.path_params}
    end
  end

  describe "routes" do
    test "declares each route as written and under /:locale" do
      paths =
        Router.__routes__()
        |> Enum.map(& &1.path)

      assert paths == [
               "/",
               "/about",
               "/products/:id",
               "/admin/:section",
               "/:locale",
               "/:locale/about",
               "/:locale/products/:id",
               "/:locale/admin/:section"
             ]
    end

    test "matches an address with and without a prefix" do
      assert match(Router, "/about") == {"/about", %{}}
      assert match(Router, "/fr/about") == {"/:locale/about", %{"locale" => "fr"}}
      assert match(Router, "/") == {"/", %{}}
      assert match(Router, "/fr") == {"/:locale", %{"locale" => "fr"}}

      assert match(Router, "/zh-hant/products/7") ==
               {"/:locale/products/:id", %{"locale" => "zh-hant", "id" => "7"}}

      assert match(Router, "/fr/admin/users") ==
               {"/:locale/admin/:section", %{"locale" => "fr", "section" => "users"}}
    end

    test "takes the parameter's name from :param, and keeps route helpers working" do
      assert match(HelpersRouter, "/fr/pages/1") ==
               {"/:lang/pages/:page", %{"lang" => "fr", "page" => "1"}}

      helpers = HelpersRouter.Helpers
      assert helpers.page_path(Endpoint, :show, 1) == "/pages/1"
      assert helpers.page_path(Endpoint, :show, "fr", 1) == "/fr/pages/1"
    end
  end

  describe "a LiveView" do
    test "connects to an address with and without a prefix" do
      {:ok, _view, html} = live(build_conn(), "/fr/about")
      assert text(html, "locale") == "fr"

      {:ok, _view, html} = live(build_conn(), "/about")
      assert text(html, "locale") == "none"
    end

    test "patches within a language" do
      {:ok, view, _html} = live(build_conn(), "/fr/about")

      html = render_hook(view, "patch", %{"to" => "/fr/about?page=2"})
      assert text(html, "uri") == "http://www.example.com/fr/about?page=2"
    end

    test "navigates live to the same page in another language, and to the unprefixed one" do
      {:ok, view, _html} = live(build_conn(), "/fr/about")
      render_hook(view, "navigate", %{"to" => "/de/about"})
      assert_redirect(view, "/de/about")

      {:ok, view, html} = live(build_conn(), "/de/about")
      assert text(html, "locale") == "de"

      render_hook(view, "navigate", %{"to" => "/about"})
      assert_redirect(view, "/about")
    end
  end

  describe "verified routes" do
    test "verify both the plain and the prefixed address" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string("""
              defmodule Localize.LocalePrefixTest.Verified do
                use Phoenix.VerifiedRoutes,
                  router: Localize.LocalePrefixTest.Router,
                  endpoint: Localize.LocalePrefixTest.Endpoint

                def plain do
                  ~p"/about"
                end

                def localized(locale) do
                  ~p"/\#{locale}/about"
                end

                def missing do
                  ~p"/about/nowhere"
                end

                def one_segment do
                  ~p"/nowhere"
                end
              end
          """)
        end)

      verified = Module.concat(Localize.LocalePrefixTest, Verified)

      assert warnings =~ ~s|matches "/about/nowhere"|
      refute warnings =~ ~s|matches "/about"|
      refute warnings =~ ~s|/about"|

      # The root route's prefixed copy, `/:locale`, matches any path of one
      # segment, so a mistyped one is not caught.
      refute warnings =~ ~s|matches "/nowhere"|

      assert verified.plain() == "/about"
      assert verified.localized("fr") == "/fr/about"
    end
  end

  describe "compile-time checks" do
    defp compile_router(routes, options \\ "") do
      name = "Localize.LocalePrefixTest.Router#{System.unique_integer([:positive])}"

      Code.compile_string("""
      defmodule #{name} do
        use Phoenix.Router
        import Phoenix.LiveView.Router, warn: false
        import Localize.Routes, only: [locale_prefix: 1, locale_prefix: 2], warn: false

        locale_prefix #{options} do
          #{routes}
        end
      end
      """)
    end

    test "refuses a route or scope whose first segment is dynamic" do
      for routes <- [
            ~s|get "/:category/:slug", PageController, :show|,
            ~s|get "/*path", PageController, :show|,
            ~s|live "/:slug", Localize.LocalePrefixTest.PageLive|,
            ~s|resources "/:owner/posts", PageController|,
            ~s|match :*, "/:any", PageController, :show|,
            ~s|scope "/:tenant" do get "/x", PageController, :show end|,
            ~s|scope "/" do get "/:slug", PageController, :show end|,
            ~s|scope path: "/:tenant" do get "/x", PageController, :show end|,
            ~s|scope "/", Foo do scope "/" do get "/:slug", PageController, :show end end|
          ] do
        assert_raise ArgumentError, ~r/is dynamic/, fn -> compile_router(routes) end
      end
    end

    test "allows a dynamic segment after a literal first segment" do
      assert [_ | _] =
               compile_router(~s|scope "/blog" do get "/:slug", PageController, :show end|)
    end

    test "refuses forward, live_session and nested blocks" do
      for {routes, message} <- [
            {~s|forward "/api", PageController|, ~r/forwards to a plug only once/},
            {~s|live_session :inner do live "/x", Localize.LocalePrefixTest.PageLive end|,
             ~r/inside the live_session/},
            {~s|locale_prefix do get "/x", PageController, :show end|, ~r/cannot declare/}
          ] do
        assert_raise ArgumentError, message, fn -> compile_router(routes) end
      end
    end

    test "refuses options it cannot use" do
      for options <- [~s|param: :locale|, ~s|param: "1x"|, ~s|param: ""|, ~s|prefix: "x"|] do
        assert_raise ArgumentError, ~r/locale_prefix\/2/, fn ->
          compile_router(~s|get "/x", PageController, :show|, options)
        end
      end
    end
  end
end
