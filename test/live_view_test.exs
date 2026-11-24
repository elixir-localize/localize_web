defmodule Localize.LiveViewTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import ExUnit.CaptureIO

  @endpoint MyApp.LiveEndpoint

  defp text(html, id) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("##{id}")
    |> LazyHTML.text()
  end

  defp live_session_name(path) do
    %{phoenix_live_view: {_view, _action, _options, live_session}} =
      Phoenix.Router.route_info(MyApp.LiveRouter, "GET", path, "localhost")

    live_session.name
  end

  describe "localize_live_session/3" do
    test "renders a localized route in its locale on the static and connected mount" do
      conn = get(build_conn(), "/fr/vid%C3%A9o")
      assert text(html_response(conn, 200), "locale") == "fr"

      {:ok, _view, html} = live(conn)
      assert text(html, "locale") == "fr"
      assert text(html, "gettext") == "fr"
      assert text(html, "title") == "vidéo"
    end

    @tag :capture_log
    test "a live navigation to another locale is a full page load in the new locale" do
      {:ok, view, html} = live(build_conn(), "/en/video")
      assert text(html, "locale") == "en"

      assert {:error, {:redirect, %{to: to}}} = live_redirect(view, to: "/fr/vid%C3%A9o")
      assert URI.parse(to).path == "/fr/vid%C3%A9o"

      {:ok, _view, html} = live(build_conn(), to)
      assert text(html, "locale") == "fr"
    end

    test "mounts a route of Gettext locale it in the route's locale it-CH" do
      conn = get(build_conn(), "/it-ch/video_it")
      html = html_response(conn, 200)
      assert text(html, "locale") == "it-CH"
      assert text(html, "gettext") == "it"

      {:ok, _view, html} = live(conn)
      assert text(html, "locale") == "it-CH"
      assert text(html, "gettext") == "it"
    end

    test "a live navigation within one locale stays live" do
      {:ok, view, _html} = live(build_conn(), "/fr/vid%C3%A9o")
      assert {:ok, _view, html} = live_redirect(view, to: "/fr/audio")
      assert text(html, "locale") == "fr"
    end

    test "the route locale wins over a stale session locale" do
      conn = Plug.Test.init_test_session(build_conn(), %{"localize_locale" => "de"})
      {:ok, _view, html} = live(conn, "/fr/vid%C3%A9o")
      assert text(html, "locale") == "fr"
    end

    test "puts each locale's routes in their own live session" do
      assert live_session_name("/en/video") == :localized_en
      assert live_session_name("/fr/vidéo") == :localized_fr
      assert live_session_name("/de/video") == :localized_de
      assert live_session_name("/fr/mapped") == :mapped_fr
      assert live_session_name("/live") == :plain
    end

    test "keeps the locales named by localize/2" do
      assert live_session_name("/fr/pair") == :localized_fr
      assert :error = Phoenix.Router.route_info(MyApp.LiveRouter, "GET", "/de/pair", "localhost")

      assert :error =
               Phoenix.Router.route_info(MyApp.LiveRouter, "GET", "/en/mapped", "localhost")
    end

    test "adds the locale to a session given as an MFA" do
      {:ok, _view, html} = live(build_conn(), "/en/video")
      assert text(html, "extra") == "mfa"
    end

    test "adds the locale to a session given as a map" do
      {:ok, _view, html} = live(build_conn(), "/fr/mapped")
      assert text(html, "extra") == "map"
      assert text(html, "locale") == "fr"
    end

    test "raises when a route is not inside a localize block" do
      assert_raise ArgumentError,
                   ~r/live "\/live" in localize_live_session\/3 is not inside/,
                   fn ->
                     compile_router("""
                     localize_live_session :bad do
                       live "/live", MyAppWeb.LocaleLive
                     end
                     """)
                   end
    end

    test "raises when :session_key is not a non-empty string" do
      for session_key <- ["\"\"", "42", ":admin"] do
        assert_raise ArgumentError, ~r/expects :session_key to be a non-empty string/, fn ->
          compile_router("""
          localize_live_session :bad, session_key: #{session_key} do
            localize do
              live "/\#{locale}/video", MyAppWeb.LocaleLive
            end
          end
          """)
        end
      end
    end

    test "raises when the options are not a keyword list" do
      assert_raise ArgumentError, ~r/expects its options as a keyword list/, fn ->
        compile_router("""
        options = [on_mount: MyAppWeb.LocaleHook]

        localize_live_session :bad, options do
          localize do
            live "/\#{locale}/video", MyAppWeb.LocaleLive
          end
        end
        """)
      end
    end

    test "warns about a localized live route outside localize_live_session/3" do
      warning =
        capture_io(:stderr, fn ->
          compile_router("""
          live_session :outside do
            localize do
              live "/\#{locale}/outside", MyAppWeb.LocaleLive
            end
          end
          """)
        end)

      assert warning =~ ~s(live "/\#{locale}/outside" is localized for more than one locale)
    end

    test "does not warn about a live route localized for one locale" do
      warning =
        capture_io(:stderr, fn ->
          compile_router("""
          live_session :single do
            localize "fr" do
              live "/\#{locale}/single", MyAppWeb.LocaleLive
            end
          end
          """)
        end)

      # stderr is shared with concurrently running async tests, so check
      # for this warning rather than for no output at all.
      refute warning =~ "is localized for more than one locale"
    end
  end

  describe "__live_session__/4" do
    test "adds the locale under the session key to no session, a map and an MFA" do
      conn = build_conn()
      key = "localize_locale"

      assert Localize.Routes.__live_session__(conn, "fr", nil, key) == %{key => "fr"}

      assert Localize.Routes.__live_session__(conn, "fr", %{"a" => 1}, key) ==
               %{"a" => 1, key => "fr"}

      assert Localize.Routes.__live_session__(
               conn,
               "fr",
               {MyAppWeb.LocaleHook, :session, ["x"]},
               key
             ) ==
               %{"extra" => "x", key => "fr"}

      assert Localize.Routes.__live_session__(conn, "fr", nil, "page_locale") == %{
               "page_locale" => "fr"
             }
    end
  end

  describe "a session key of its own" do
    test "the admin stores and reads its locale under its own key" do
      conn = get(build_conn(), "/admin/dashboard?locale=de")

      assert text(html_response(conn, 200), "locale") == "de"
      assert Plug.Conn.get_session(conn, "admin_locale") == "de"
      assert Plug.Conn.get_session(conn, "localize_locale") == nil

      {:ok, _view, html} = live(conn)
      assert text(html, "locale") == "de"
      assert text(html, "gettext") == "de"
    end

    test "the pages and the admin keep two locales apart" do
      admin = get(build_conn(), "/admin/dashboard?locale=de")
      pages = get(recycle(admin), "/live?locale=fr")

      assert Plug.Conn.get_session(pages, "localize_locale") == "fr"
      assert Plug.Conn.get_session(pages, "admin_locale") == "de"

      admin_again = get(recycle(pages), "/admin/dashboard")
      assert text(html_response(admin_again, 200), "locale") == "de"
    end

    test "a localized live session puts the route's locale under the key" do
      {:ok, _view, html} = live(build_conn(), "/de/keyed")
      assert text(html, "locale") == "de"
    end
  end

  defp compile_router(routes) do
    module = "LiveRouter#{System.unique_integer([:positive])}"

    Code.compile_string("""
    defmodule Localize.LiveViewTest.#{module} do
      use Phoenix.Router
      use Localize.Routes, gettext: MyApp.Gettext, helpers: false
      import Phoenix.LiveView.Router

      #{routes}
    end
    """)
  end

  describe "live_session_locale/1, when only a chosen locale is stored" do
    @default_locale Localize.LanguageTag.to_string(Localize.default_locale())

    defp french_browser do
      Plug.Conn.put_req_header(build_conn(), "accept-language", "fr")
    end

    test "hands the connected mount a locale that is not in the session cookie" do
      conn = get(french_browser(), "/chosen/handed")

      assert text(html_response(conn, 200), "locale") == "fr"
      assert Localize.Plug.PutLocale.get_locale_source(conn) == :accept_language
      assert Plug.Conn.get_session(conn, "localize_locale") == nil
      refute Map.has_key?(conn.resp_cookies, "_live")

      {:ok, _view, html} = live(conn)
      assert text(html, "locale") == "fr"
      assert text(html, "gettext") == "fr"
    end

    test "without it the connected mount falls back to the default locale" do
      conn = get(french_browser(), "/chosen/cookie-only")

      assert text(html_response(conn, 200), "locale") == "fr"
      assert Plug.Conn.get_session(conn, "localize_locale") == nil

      {:ok, _view, html} = live(conn)
      assert text(html, "locale") == @default_locale
    end

    test "a locale the visitor chose is stored, and reaches the connected mount either way" do
      for path <- ["/chosen/handed", "/chosen/cookie-only"] do
        conn = get(french_browser(), path <> "?locale=de")

        assert text(html_response(conn, 200), "locale") == "de"
        assert Plug.Conn.get_session(conn, "localize_locale") == "de"

        {:ok, _view, html} = live(conn)
        assert text(html, "locale") == "de"
      end
    end
  end
end
