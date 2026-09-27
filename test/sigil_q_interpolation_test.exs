defmodule SigilQInterpolationTest do
  use ExUnit.Case, async: false

  # Regression coverage for the `#{locale}` / `#{language}` / `#{territory}`
  # interpolation forms in `~q`, documented in the "Locale Interpolation in
  # ~q" section of guides/phoenix-localized-routing.md.
  #
  # These forms substitute a token at compile time, once per locale branch.
  # Substituting only the inner `Kernel.to_string/1` call left the enclosing
  # `::binary` wrapper in place, so Phoenix saw `<<"/", "en"::binary,
  # "/users">>` — a literal inside a dynamic wrapper, which matches none of
  # its `verify_segment/3` clauses — and raised "a dynamic ~p interpolation
  # must follow a static segment". Every test here failed before the fix.

  use Localize.VerifiedRoutes,
    router: MyApp.Router,
    endpoint: MyApp.Endpoint,
    gettext: MyApp.Gettext

  describe "\#{locale} in first position" do
    test "resolves for each locale, alongside path translation" do
      Localize.put_locale(:en)
      assert ~q"/#{locale}/locale/pages/1" == "/en/locale/pages/1"

      Localize.put_locale(:fr)
      assert ~q"/#{locale}/locale/pages/1" == "/fr/locale/pages_fr/1"

      Localize.put_locale(:de)
      assert ~q"/#{locale}/locale/pages/1" == "/de/locale/pages_de/1"
    end
  end

  describe "\#{language} in first position" do
    test "resolves to the language subtag" do
      Localize.put_locale(:en)
      assert ~q"/#{language}/language/pages/1" == "/en/language/pages/1"

      Localize.put_locale(:fr)
      assert ~q"/#{language}/language/pages/1" == "/fr/language/pages_fr/1"

      Localize.put_locale(:de)
      assert ~q"/#{language}/language/pages/1" == "/de/language/pages_de/1"
    end
  end

  describe "\#{territory} in first position" do
    test "resolves to the territory subtag, which differs from the language" do
      # en maps to US — the case that distinguishes territory from language.
      Localize.put_locale(:en)
      assert ~q"/#{territory}/territory/pages/1" == "/us/territory/pages/1"

      Localize.put_locale(:fr)
      assert ~q"/#{territory}/territory/pages/1" == "/fr/territory/pages_fr/1"

      Localize.put_locale(:de)
      assert ~q"/#{territory}/territory/pages/1" == "/de/territory/pages_de/1"
    end
  end

  describe "interpolation in a non-first segment" do
    test "resolves when the token is preceded by static and dynamic segments" do
      Localize.put_locale(:en)
      assert ~q"/users/1/faces/2/#{locale}/visages" == "/users/1/face/2/en/visages"

      Localize.put_locale(:fr)
      assert ~q"/users/1/faces/2/#{locale}/visages" == "/users_fr/1/faces_fr/2/fr/visages"

      Localize.put_locale(:de)
      assert ~q"/users/1/faces/2/#{locale}/visages" == "/users_de/1/faces_de/2/de/visages"
    end

    test "coexists with genuine runtime interpolation in the same path" do
      user_id = 7
      face_id = 9

      Localize.put_locale(:en)

      assert ~q"/users/#{user_id}/faces/#{face_id}/#{locale}/visages" ==
               "/users/7/face/9/en/visages"

      Localize.put_locale(:fr)

      assert ~q"/users/#{user_id}/faces/#{face_id}/#{locale}/visages" ==
               "/users_fr/7/faces_fr/9/fr/visages"
    end

    test "runtime values are still interpolated at runtime, not frozen" do
      Localize.put_locale(:en)

      for id <- [1, 2, 3] do
        assert ~q"/users/#{id}/faces/2/#{locale}/visages" == "/users/#{id}/face/2/en/visages"
      end
    end
  end

  describe "query strings" do
    test "a static query survives interpolation" do
      Localize.put_locale(:en)
      assert ~q"/#{locale}/locale/pages/1?draft=true" == "/en/locale/pages/1?draft=true"
    end

    test "a dynamic query survives interpolation" do
      Localize.put_locale(:en)

      assert ~q"/#{locale}/locale/pages/1?#{[draft: true]}" ==
               "/en/locale/pages/1?draft=true"
    end
  end

  describe "url/1 with an interpolated route" do
    test "produces a full URL" do
      Localize.put_locale(:fr)
      assert url(~q"/#{locale}/locale/pages/1") == "http://localhost/fr/locale/pages_fr/1"
    end
  end

  describe "path_for/2 and url_for/2 with an interpolated route" do
    test "render a specific locale without changing the process locale" do
      Localize.put_locale(:en)

      assert path_for(:fr, "/#{locale}/locale/pages/1") == "/fr/locale/pages_fr/1"
      assert path_for(:de, "/#{locale}/locale/pages/1") == "/de/locale/pages_de/1"

      # The process locale is untouched.
      assert Localize.get_locale().cldr_locale_id == :en
    end
  end

  describe "regressions: the other supported forms still work" do
    test "the :locale colon form is unaffected" do
      Localize.put_locale(:de)
      assert ~q[/users/:locale] == "/users_de/de"
      assert ~q[/users/:language] == "/users_de/de"
      assert ~q[/users/:territory] == "/users_de/de"
    end

    test "a route with no interpolation is unaffected" do
      Localize.put_locale(:en)
      assert ~q"/users" == "/users"

      Localize.put_locale(:fr)
      assert ~q"/users" == "/users_fr"
    end

    test "runtime-only interpolation is unaffected" do
      Localize.put_locale(:en)
      assert ~q"/users/17?#{[admin: true]}" == "/users/17?admin=true"
    end
  end
end
