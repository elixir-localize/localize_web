defmodule Localize.Routes.Test do
  use ExUnit.Case
  import Plug.Test
  import Localize.Route.TestHelper

  import Phoenix.ConnTest,
    only: [
      build_conn: 0,
      get: 2
    ]

  describe "Routes" do
    test "Localized route generation" do
      assert Phoenix.Router.route_info(MyApp.Router, "GET", "/pages/1", "myhost") ==
               %{
                 log: :debug,
                 path_params: %{"page" => "1"},
                 pipe_through: [],
                 plug: PageController,
                 plug_opts: :show,
                 route: "/pages/:page"
               }

      assert Phoenix.Router.route_info(MyApp.Router, "GET", "/pages_fr/1", "myhost") ==
               %{
                 log: :debug,
                 path_params: %{"page" => "1"},
                 pipe_through: [],
                 plug: PageController,
                 plug_opts: :show,
                 route: "/pages_fr/:page"
               }
    end

    test "Not localized route generation" do
      assert Phoenix.Router.route_info(MyApp.Router, "GET", "/not_localized/:page", "myhost") ==
               %{
                 log: :debug,
                 path_params: %{"page" => ":page"},
                 pipe_through: [],
                 plug: NotLocalizedController,
                 plug_opts: :show,
                 route: "/not_localized/:page"
               }
    end
  end

  describe "Routing" do
    test "Localized routing" do
      opts = MyApp.Router.init([])

      conn =
        :get
        |> conn("/pages_fr/1")
        |> MyApp.Router.call(opts)

      assert Map.get(conn.private, :phoenix_action) == :show
      assert Map.get(conn.private, :phoenix_controller) == PageController
      assert conn.path_info == ["pages_fr", "1"]
      assert %{localize_locale: %Localize.LanguageTag{cldr_locale_id: :fr}} = conn.private
    end
  end

  describe "Helpers" do
    test "localized path helpers" do
      Localize.put_locale(:en)
      assert MyApp.Router.LocalizedHelpers.page_path(%Plug.Conn{}, :show, 1) == "/pages/1"

      Localize.put_locale(:fr)
      assert MyApp.Router.LocalizedHelpers.page_path(%Plug.Conn{}, :show, 1) == "/pages_fr/1"
    end

    test "localized path helper with configured :as" do
      Localize.put_locale(:fr)
      assert MyApp.Router.LocalizedHelpers.chap_path(%Plug.Conn{}, :show, 1) == "/chapters_fr/1"
    end

    test "no localized path helper" do
      Localize.put_locale(:en)

      assert MyApp.Router.LocalizedHelpers.not_localized_path(%Plug.Conn{}, :show, 1) ==
               "/not_localized/1"

      Localize.with_locale(:fr, fn ->
        assert MyApp.Router.LocalizedHelpers.not_localized_path(%Plug.Conn{}, :show, 1) ==
                 "/not_localized/1"

        assert MyApp.Router.LocalizedHelpers.user_face_path(%Plug.Conn{}, :index, 1,
                 thing: :other
               ) ==
                 "/users_fr/1/faces_fr?thing=other"
      end)
    end
  end

  describe "Interpolate during route generation" do
    test "interpolating a locale" do
      assert find_route(MyApp.Router, "/de/locale/pages_de/:page") ==
               %{
                 helper: "with_locale_de",
                 metadata: %{log: :debug},
                 path: "/de/locale/pages_de/:page",
                 plug: PageController,
                 plug_opts: :show,
                 verb: :get
               }
    end

    test "interpolating a language" do
      assert find_route(MyApp.Router, "/de/language/pages_de/:page") ==
               %{
                 helper: "with_language_de",
                 metadata: %{log: :debug},
                 path: "/de/language/pages_de/:page",
                 plug: PageController,
                 plug_opts: :show,
                 verb: :get
               }
    end

    test "interpolating a territory" do
      assert find_route(MyApp.Router, "/de/territory/pages_de/:page") ==
               %{
                 helper: "with_territory_de",
                 metadata: %{log: :debug},
                 path: "/de/territory/pages_de/:page",
                 plug: PageController,
                 plug_opts: :show,
                 verb: :get
               }
    end

    @endpoint MyApp.Router

    test "That :private propagates to the connection" do
      {:ok, locale} = Localize.validate_locale(:en)
      conn = get(build_conn(), "/users/1")
      assert conn.private.localize_locale == locale

      {:ok, locale} = Localize.validate_locale(:de)
      conn = get(build_conn(), "/users_de/1")
      assert conn.private.localize_locale == locale
    end

    @endpoint MyApp.Endpoint

    test "hreflang link helper" do
      conn = get(build_conn(), "/users/1")

      links = MyApp.Router.LocalizedHelpers.user_links(conn, :show, 1)
      header_io_data = MyApp.Router.LocalizedHelpers.hreflang_links(links)
      header = Phoenix.HTML.safe_to_string(header_io_data)

      assert links == %{
               "de" => "http://localhost/users_de/1",
               "en" => "http://localhost/users/1",
               "fr" => "http://localhost/users_fr/1"
             }

      assert header =~ ~s|hreflang="de"|
      assert header =~ ~s|hreflang="en"|
      assert header =~ ~s|hreflang="fr"|
      assert header =~ ~s|rel="alternate"|
    end

    test "hreflang test helper for non-localized route" do
      conn = get(build_conn(), "/not_localized/1")

      links = MyApp.Router.LocalizedHelpers.not_localized_links(conn, :show, 1)
      header_io_data = MyApp.Router.LocalizedHelpers.hreflang_links(links)
      header = Phoenix.HTML.safe_to_string(header_io_data)

      assert links == %{}
      assert header_io_data == {:safe, []}
      assert header == ""
    end
  end
end
