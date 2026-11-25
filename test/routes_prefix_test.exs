defmodule Localize.Routes.PrefixTest do
  use ExUnit.Case, async: true

  alias Localize.Routes.Prefix

  doctest Localize.Routes.Prefix

  @supported ["en", "fr", :"zh-Hant"]

  defp locale_id({:ok, {nil, rest}}) do
    {nil, rest}
  end

  defp locale_id({:ok, {locale, rest}}) do
    {locale.cldr_locale_id, rest}
  end

  describe "split/2" do
    test "reads a first segment that names a supported locale, in any case and either separator" do
      for {path, expected} <- [
            {"/fr/about", {:fr, "/about"}},
            {"/FR", {:fr, "/"}},
            {"/fr/", {:fr, "/"}},
            {"/fr?page=2", {:fr, "/?page=2"}},
            {"/fr#top", {:fr, "/#top"}},
            {"/fr/a/b?c=d#e", {:fr, "/a/b?c=d#e"}},
            {"/zh-hant/blog", {:"zh-Hant", "/blog"}},
            {"/ZH_HANT", {:"zh-Hant", "/"}}
          ] do
        assert {path, locale_id(Prefix.split(path, @supported))} == {path, expected}
      end
    end

    test "reads no locale from a segment that only resembles a supported one" do
      for path <- ["/", "/about", "/fr-ca/about", "/fra", "/de/about", "/blog/fr", "/?fr", "/#fr"] do
        assert Prefix.split(path, @supported) == {:ok, {nil, path}}
      end
    end

    test "takes the locales configured for Localize by default" do
      assert locale_id(Prefix.split("/it-ch/x")) == {:"it-CH", "/x"}
      assert locale_id(Prefix.split("/pt/x")) == {nil, "/pt/x"}
    end

    test "takes atoms, strings and language tags in the supported list, and ignores other entries" do
      {:ok, french} = Localize.validate_locale("fr")

      assert locale_id(Prefix.split("/fr/x", [french])) == {:fr, "/x"}
      assert locale_id(Prefix.split("/fr/x", [nil, 42, %{}, :fr])) == {:fr, "/x"}
      assert Prefix.split("/fr/x", []) == {:ok, {nil, "/fr/x"}}
    end

    test "returns an error, never raises, for a path or list it cannot use" do
      for {path, supported} <- [
            {nil, nil},
            {"", nil},
            {"fr/about", nil},
            {~c"/fr", nil},
            {"/fr", %{}},
            {"/fr", "fr"}
          ] do
        assert {:error, %{__exception__: true}} = Prefix.split(path, supported),
               inspect({path, supported})
      end
    end
  end

  describe "path/3" do
    defp path(path, locale, options \\ []) do
      Prefix.path(path, locale, Keyword.merge([default: :en, supported: @supported], options))
    end

    test "under :prefix_others gives the default locale no prefix and the others one" do
      for {from, locale, expected} <- [
            {"/about", :en, "/about"},
            {"/about", :fr, "/fr/about"},
            {"/fr/about", :en, "/about"},
            {"/fr/about", :fr, "/fr/about"},
            {"/fr/about", "zh-Hant", "/zh-hant/about"},
            {"/zh-hant/about", :fr, "/fr/about"},
            {"/en/about", :en, "/about"}
          ] do
        assert {from, locale, path(from, locale)} == {from, locale, {:ok, expected}}
      end
    end

    test "under :prefix_all gives every locale a prefix" do
      for {from, locale, expected} <- [
            {"/about", :en, "/en/about"},
            {"/about", :fr, "/fr/about"},
            {"/fr/about", :en, "/en/about"},
            {"/en/about", :en, "/en/about"}
          ] do
        assert {from, locale, path(from, locale, mode: :prefix_all)} ==
                 {from, locale, {:ok, expected}}
      end
    end

    test "writes the root of a site without a trailing slash, and keeps a query string" do
      assert path("/", :fr) == {:ok, "/fr"}
      assert path("/fr", :en) == {:ok, "/"}
      assert path("/?q=1", :fr) == {:ok, "/fr?q=1"}
      assert path("/fr?q=1#a", :en) == {:ok, "/?q=1#a"}
      assert path("/fr/x?q=1", :en, mode: :prefix_all) == {:ok, "/en/x?q=1"}
    end

    test "matches the locale against the supported ones, as the plugs do" do
      assert path("/about", "fr-CA") == {:ok, "/fr/about"}
      assert path("/about", "zh_Hant") == {:ok, "/zh-hant/about"}

      {:ok, french} = Localize.validate_locale("fr")
      assert path("/about", french) == {:ok, "/fr/about"}
    end

    test "matches the default locale against the supported ones" do
      assert path("/fr/about", "fr-CA", default: "fr-CA") == {:ok, "/about"}
    end

    test "takes the default locale and the configured locales by default" do
      assert Prefix.path("/about", :fr) == {:ok, "/fr/about"}
      assert Prefix.path("/fr/about", :en) == {:ok, "/about"}
    end

    test "returns an error, never raises, for a path, locale or option it cannot use" do
      for {from, locale, options} <- [
            {"about", :fr, []},
            {nil, :fr, []},
            {"/about", :de, []},
            {"/about", nil, []},
            {"/about", 42, []},
            {"/about", "not a locale!", []},
            {"/about", :fr, [mode: :prefix_some]},
            {"/about", :fr, [default: :de]},
            {"/about", :fr, [supported: "fr"]},
            {"/about", :fr, [supported: []]}
          ] do
        assert {:error, %{__exception__: true}} = path(from, locale, options),
               inspect({from, locale, options})
      end

      assert {:error, %{__exception__: true}} = Prefix.path("/about", :fr, %{})
    end
  end

  describe "target/3" do
    defp target(path, locale, options \\ []) do
      result =
        Prefix.target(path, locale, Keyword.merge([default: :en, supported: @supported], options))

      case result do
        {:serve, locale} -> {:serve, locale.cldr_locale_id}
        other -> other
      end
    end

    def published?(rest, locale, published \\ %{"/about" => [:en, :fr]}) do
      locale.cldr_locale_id in Map.get(published, rest, [])
    end

    test "under :prefix_others serves a path by its prefix, and redirects the default prefix with a 301" do
      for visitor <- [:en, :fr, "zh-Hant", nil] do
        assert target("/about", visitor) == {:serve, :en}
        assert target("/fr/about", visitor) == {:serve, :fr}
        assert target("/zh-hant/about", visitor) == {:serve, :"zh-Hant"}
        assert target("/en/about", visitor) == {:redirect, "/about", 301}
        assert target("/EN", visitor) == {:redirect, "/", 301}
        assert target("/blog/fr", visitor) == {:serve, :en}
      end
    end

    test "under :prefix_all serves a prefixed path, and redirects an unprefixed one to the visitor's locale with a 302" do
      prefix_all = [mode: :prefix_all]

      assert target("/en/about", :fr, prefix_all) == {:serve, :en}
      assert target("/fr/about", :en, prefix_all) == {:serve, :fr}
      assert target("/about", :fr, prefix_all) == {:redirect, "/fr/about", 302}
      assert target("/about", :en, prefix_all) == {:redirect, "/en/about", 302}
      assert target("/about", "fr-CA", prefix_all) == {:redirect, "/fr/about", 302}
      assert target("/", "zh-Hant", prefix_all) == {:redirect, "/zh-hant", 302}
    end

    test "under :prefix_all redirects a visitor with no supported locale to the default locale" do
      for visitor <- [nil, :de, "not a locale!", 42] do
        assert target("/about", visitor, mode: :prefix_all) == {:redirect, "/en/about", 302}
      end
    end

    test "keeps the query string and fragment on a redirect" do
      assert target("/en/about?page=2#top", :fr) == {:redirect, "/about?page=2#top", 301}
      assert target("/en?page=2", :fr) == {:redirect, "/?page=2", 301}

      assert target("/about?page=2", :fr, mode: :prefix_all) ==
               {:redirect, "/fr/about?page=2", 302}

      assert target("/?page=2", :fr, mode: :prefix_all) == {:redirect, "/fr?page=2", 302}
    end

    test "redirects to the default locale when :exists? says the page is not in the visitor's" do
      for exists <- [
            &published?/2,
            {__MODULE__, :published?},
            {__MODULE__, :published?, [%{"/about" => [:en, :fr]}]}
          ] do
        options = [mode: :prefix_all, exists?: exists]

        assert target("/about", :fr, options) == {:redirect, "/fr/about", 302}
        assert target("/about", "zh-Hant", options) == {:redirect, "/en/about", 302}
        assert target("/news", :fr, options) == {:redirect, "/en/news", 302}
      end
    end

    test "takes anything :exists? returns but true as false" do
      for answer <- [false, nil, :yes, "true", {:ok, true}] do
        options = [mode: :prefix_all, exists?: fn _rest, _locale -> answer end]
        assert target("/about", :fr, options) == {:redirect, "/en/about", 302}
      end
    end

    test "consults :exists? only for a redirect under :prefix_all" do
      refuse = fn _rest, _locale -> flunk("called") end

      assert target("/fr/about", :fr, exists?: refuse) == {:serve, :fr}
      assert target("/about", :fr, exists?: refuse) == {:serve, :en}
      assert target("/fr/about", :fr, mode: :prefix_all, exists?: refuse) == {:serve, :fr}
    end

    test "matches the default locale against the supported ones" do
      assert target("/fr/about", :en, default: "fr-CA") == {:redirect, "/about", 301}
      assert target("/about", :en, default: "fr-CA") == {:serve, :fr}
    end

    test "returns an error, never raises, for a path or option it cannot use" do
      for {path, options} <- [
            {"about", []},
            {nil, []},
            {"/about", [mode: :prefix_some]},
            {"/about", [default: :de]},
            {"/about", [default: nil]},
            {"/about", [supported: "fr"]},
            {"/about", [exists?: fn _rest -> true end]},
            {"/about", [exists?: "published"]},
            {"/about", [exists?: {"Pages", :published?}]}
          ] do
        assert {:error, %{__exception__: true}} = target(path, :fr, options),
               inspect({path, options})
      end

      assert {:error, %{__exception__: true}} = Prefix.target("/about", :fr, %{})
    end
  end
end
