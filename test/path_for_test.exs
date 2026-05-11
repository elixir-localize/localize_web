defmodule PathFor.Test do
  use ExUnit.Case

  use Localize.VerifiedRoutes,
    router: MyApp.Router,
    endpoint: MyApp.Endpoint,
    gettext: MyApp.Gettext

  # `path_for/2` and `url_for/2` let the caller force a specific locale at the
  # call site, independent of the process-wide locale set by
  # `Localize.put_locale/1`. Mirrors the macros added to ex_cldr_routes for
  # https://github.com/elixir-cldr/cldr_routes/issues/18.

  describe "path_for/2" do
    test "renders the literal locale's translation regardless of current locale" do
      Localize.put_locale(:en)
      assert path_for(:fr, "/users") == "/users_fr"
      assert path_for(:de, "/users") == "/users_de"
      assert path_for(:en, "/users") == "/users"
    end

    test "does not mutate the process locale" do
      Localize.put_locale(:en)
      _ = path_for(:fr, "/users")
      assert Localize.get_locale().cldr_locale_id == :en
    end

    test "supports a runtime locale expression" do
      Localize.put_locale(:en)

      for locale <- [:en, :fr, :de] do
        expected =
          case locale do
            :en -> "/users"
            :fr -> "/users_fr"
            :de -> "/users_de"
          end

        assert path_for(locale, "/users") == expected
      end
    end

    test "supports interpolation in the route string" do
      user_id = 42
      assert path_for(:fr, "/users/#{user_id}") == "/users_fr/42"
    end

    test "supports :locale / :language / :territory interpolation" do
      assert path_for(:de, "/users/:locale") == "/users_de/de"
      assert path_for(:fr, "/users/:territory") == "/users_fr/fr"
    end

    test "renders multiple locales in one template-style pass" do
      Localize.put_locale(:en)

      pairs =
        for locale <- [:en, :fr, :de] do
          {locale, path_for(locale, "/users")}
        end

      assert pairs == [{:en, "/users"}, {:fr, "/users_fr"}, {:de, "/users_de"}]
    end
  end

  describe "url_for/2" do
    test "renders a full URL in the specified locale" do
      Localize.put_locale(:en)
      assert url_for(:fr, "/users") == "http://localhost/users_fr"
      assert url_for(:de, "/users") == "http://localhost/users_de"
      assert url_for(:en, "/users") == "http://localhost/users"
    end

    test "supports interpolations" do
      assert url_for(:de, "/users/:locale") == "http://localhost/users_de/de"
    end
  end
end
