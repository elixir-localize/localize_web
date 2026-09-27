defmodule Localize.RouterCompileTest do
  # Compiling a router runs the `localize` macros and generates the
  # localized helpers. The fixture routers in test/support are compiled
  # before the tests start, so this compiles the same router again at
  # runtime to exercise that code under test.
  use ExUnit.Case, async: false

  @router_source File.read!("test/support/router.ex")

  setup_all do
    router = Module.concat(__MODULE__, "Router#{System.unique_integer([:positive])}")

    source =
      @router_source
      |> String.replace("defmodule MyApp.Router do", "defmodule #{inspect(router)} do")
      |> String.replace("localize_live_session :default do", "localize_live_session :compiled do")

    Code.compile_string(source)

    %{router: router, helpers: Module.concat(router, LocalizedHelpers)}
  end

  test "defines the same routes as the fixture router", %{router: router} do
    paths = fn router -> router.__routes__() |> Enum.map(& &1.path) |> Enum.sort() end
    assert paths.(router) == paths.(MyApp.Router)
  end

  test "localized helpers dispatch on the current locale", %{helpers: helpers} do
    Localize.put_locale(:fr)
    assert helpers.page_path(%Plug.Conn{}, :show, 1) == "/pages_fr/1"
    assert helpers.user_face_path(%Plug.Conn{}, :index, 1) == "/users_fr/1/faces_fr"

    Localize.put_locale(:en)
    assert helpers.page_path(%Plug.Conn{}, :show, 1) == "/pages/1"
  end

  test "localized helpers raise for an unknown action", %{helpers: helpers} do
    Localize.put_locale(:en)

    assert_raise ArgumentError, ~r/no action :nope/, fn ->
      helpers.page_path(%Plug.Conn{}, :nope, 1)
    end
  end

  describe "compile-time errors" do
    defp compile_routes(routes) do
      module = Module.concat(__MODULE__, "Routes#{System.unique_integer([:positive])}")

      Code.compile_string("""
      defmodule #{inspect(module)} do
        use Phoenix.Router
        use Localize.Routes, gettext: MyApp.Gettext, helpers: false
        #{if routes =~ "live ", do: "import Phoenix.LiveView.Router"}

        #{routes}
      end
      """)

      module
    end

    test "a verb that cannot be localized raises" do
      assert_raise ArgumentError, ~r/Invalid route for localization: forward/, fn ->
        compile_routes(~s|localize [:en] do\n forward "/x", PageController\n end|)
      end
    end

    test "an invalid locale raises" do
      assert_raise Localize.InvalidLocaleError, fn ->
        compile_routes(~s|localize ["!!!"] do\n get "/x", PageController, :show\n end|)
      end
    end

    test "localize_live_session/3 keeps only the locales a localize block names" do
      module =
        compile_routes("""
        localize_live_session :pair do
          localize [:en, :fr] do
            live "/\#{locale}/pair", MyAppWeb.LocaleLive
          end
        end
        """)

      names =
        for route <- module.__routes__() do
          {_view, _action, _options, live_session} = route.metadata.phoenix_live_view
          live_session.name
        end

      assert Enum.sort(names) == [:pair_en, :pair_fr]
    end

    test "localizable_verbs/0 lists the route macros localize/1 accepts" do
      assert :live in Localize.Routes.localizable_verbs()
      assert :resources in Localize.Routes.localizable_verbs()
    end
  end
end
