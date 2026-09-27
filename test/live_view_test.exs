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

      assert warning == ""
    end
  end

  describe "__live_session__/3" do
    test "adds the locale to no session, a map and an MFA" do
      conn = build_conn()

      assert Localize.Routes.__live_session__(conn, "fr", nil) == %{"localize_locale" => "fr"}

      assert Localize.Routes.__live_session__(conn, "fr", %{"a" => 1}) ==
               %{"a" => 1, "localize_locale" => "fr"}

      assert Localize.Routes.__live_session__(conn, "fr", {MyAppWeb.LocaleHook, :session, ["x"]}) ==
               %{"extra" => "x", "localize_locale" => "fr"}
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
end
