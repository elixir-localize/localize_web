defmodule SubsetLocales.Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  use Localize.VerifiedRoutes,
    router: MyApp.Router,
    endpoint: MyApp.Endpoint,
    gettext: MyApp.Gettext

  alias MyApp.Router.LocalizedHelpers, as: Helpers

  # The test router declares `resources "/comments"` inside
  # `localize [:en, :fr, :de]`, and the `chap` routes for `:fr` only. The
  # Gettext locales are de, en, fr and it, so `it-CH` has translations but
  # none of these routes: it must get the default locale's route, as `th`,
  # which has no translations, already does.

  setup do
    Localize.put_locale(:en)
    :ok
  end

  describe "path_for/3 with :locales" do
    test "renders each declared locale's route" do
      assert path_for(:en, "/comments", locales: [:en, :fr, :de]) == "/comments"
      assert path_for(:fr, "/comments", locales: [:en, :fr, :de]) == "/comments_fr"
      assert path_for(:de, "/comments", locales: [:en, :fr, :de]) == "/comments_de"
    end

    test "renders the default locale's route for a locale with translations but no route" do
      assert path_for(:"it-CH", "/comments", locales: [:en, :fr, :de]) == "/comments"
    end

    test "renders the default locale's route for a locale without translations or an invalid one" do
      for locale <- [:th, "xx-bogus", nil] do
        assert path_for(locale, "/comments", locales: [:en, :fr, :de]) == "/comments"
      end
    end

    test "falls back to the first declared locale when the default is not declared" do
      assert path_for(:en, "/comments", locales: [:fr, :de]) == "/comments_de"
    end

    test "dispatches on the current locale" do
      Localize.put_locale(:"it-CH")
      assert path_for(Localize.get_locale(), "/comments", locales: [:en, :fr, :de]) == "/comments"

      Localize.put_locale(:fr)

      assert path_for(Localize.get_locale(), "/comments", locales: [:en, :fr, :de]) ==
               "/comments_fr"
    end

    test "resolves the listed ids as the router does" do
      # `"fr"` and `:"fr-CA"` both resolve to the `fr` routes.
      assert path_for(:fr, "/comments", locales: ["en", :"fr-CA"]) == "/comments_fr"
    end
  end

  describe "url_for/3 with :locales" do
    test "renders the default locale's URL for a locale outside the list" do
      assert url_for(:"it-CH", "/comments", locales: [:en, :fr, :de]) ==
               "http://localhost/comments"

      assert url_for(:fr, "/comments", locales: [:en, :fr, :de]) ==
               "http://localhost/comments_fr"
    end
  end

  describe "hreflang_links/2 with :locales" do
    test "annotates only the declared locales" do
      assert {:ok, safe} = hreflang_links("/comments", locales: [:en, :fr, :de])
      html = Phoenix.HTML.safe_to_string(safe)

      assert html =~ ~s(href="http://localhost/comments" hreflang="en")
      assert html =~ ~s(href="http://localhost/comments_fr" hreflang="fr")
      assert html =~ ~s(href="http://localhost/comments_de" hreflang="de")
      refute html =~ "it-CH"
    end

    test "takes the options of Localize.HTML.Hreflang.links/2 beside it" do
      assert {:ok, safe} = hreflang_links("/comments", locales: [:en, :fr], canonicalize: false)
      html = Phoenix.HTML.safe_to_string(safe)

      assert html =~ ~s(hreflang="fr")
      refute html =~ ~s(hreflang="de")
    end
  end

  describe ":locales at compile time" do
    test "a locale without Gettext translations is warned of and skipped" do
      warning =
        capture_io(:stderr, fn ->
          compile_probe(~s|path_for(locale, "/comments", locales: [:en, :ja])|)
        end)

      assert warning =~ ":ja has no associated gettext locale"
    end

    test "an invalid locale raises" do
      assert_raise Localize.InvalidLocaleError, fn ->
        compile_probe(~s|path_for(locale, "/comments", locales: [:en, "xx-bogus-"])|)
      end
    end

    test "a list that is not literal locale ids raises" do
      for locales <- ["[]", "nil", "[1]", "@locales"] do
        assert_raise ArgumentError, ~r/:locales/, fn ->
          compile_probe(~s|path_for(locale, "/comments", locales: #{locales})|)
        end
      end
    end

    test "options that are not a literal keyword list raise" do
      assert_raise ArgumentError, ~r/literal keyword list/, fn ->
        compile_probe(~s|path_for(locale, "/comments", options)|)
      end
    end
  end

  describe "router helpers for routes in a subset of locales" do
    test "an action outside the current locale's routes gets the default locale's route" do
      Localize.put_locale(:"it-CH")

      assert Helpers.page_path(%Plug.Conn{}, :index) == "/comments"
      assert Helpers.page_url(MyApp.Endpoint, :index) == "http://localhost/comments"
    end

    test "an action of the same helper with a route in the locale keeps it" do
      # `get "/pages/:page"` shares `page_path` with the comments and is in every locale.
      Localize.put_locale(:"it-CH")
      assert Helpers.page_path(%Plug.Conn{}, :show, 1) == "/pages_it/1"
    end

    test "falls back to the first locale with the route when the default has none" do
      assert Helpers.chap_path(%Plug.Conn{}, :show, 1) == "/chapters_fr/1"
    end
  end

  defp compile_probe(call) do
    module = "SubsetLocales.Probe#{System.unique_integer([:positive])}"

    Code.compile_string("""
    defmodule #{module} do
      use Localize.VerifiedRoutes,
        router: MyApp.Router,
        endpoint: MyApp.Endpoint,
        gettext: MyApp.Gettext

      def path(locale, options) do
        _ = options
        #{call}
      end
    end
    """)
  end
end
