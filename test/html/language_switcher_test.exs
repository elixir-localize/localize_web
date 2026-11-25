defmodule Localize.HTML.LanguageSwitcherTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  alias Localize.HTML.LanguageSwitcher

  doctest Localize.HTML.LanguageSwitcher

  @urls %{
    "en" => "/en/about",
    "fr" => "/fr/a-propos",
    "ar" => "/ar/about",
    "ja" => "/ja/about",
    "x-default" => "/about"
  }

  defp entries(urls, options) do
    {:ok, entries} = LanguageSwitcher.links(urls, options)
    entries
  end

  describe "links/2" do
    test "names each language in itself, cased for a menu, with its lang and dir" do
      by_locale = Map.new(entries(@urls, current: :en), &{&1.locale, &1})

      assert by_locale["fr"].name == "Français"
      assert by_locale["en"].name == "English"
      assert by_locale["ar"].name == "العربية"
      assert by_locale["ja"].name == "日本語"

      assert {by_locale["ar"].lang, by_locale["ar"].dir} == {"ar", "rtl"}
      assert {by_locale["fr"].lang, by_locale["fr"].dir} == {"fr", "ltr"}
      assert by_locale["fr"].url == "/fr/a-propos"
    end

    test "leaves out x-default, which names no language" do
      locales = @urls |> entries(current: :en) |> Enum.map(& &1.locale)

      refute "x-default" in locales
      assert length(locales) == 4
    end

    test "sorts by name in the collation of the current locale" do
      assert @urls |> entries(current: :fr) |> Enum.map(& &1.locale) == ["en", "fr", "ar", "ja"]
    end

    test "marks the entry the current locale matches, as the plugs match it" do
      current = fn options ->
        @urls |> entries(options) |> Enum.filter(& &1.current?) |> Enum.map(& &1.locale)
      end

      assert current.(current: :ar) == ["ar"]
      assert current.(current: "fr-CA") == ["fr"]
      assert current.(current: :th) == []
    end

    test "takes the current locale by default, and atoms or language tags as keys" do
      {:ok, _locale} = Localize.put_locale(:fr)
      {:ok, german} = Localize.validate_locale("de")

      entries = entries(%{:fr => "/fr", german => "/de"}, [])

      assert Enum.map(entries, &{&1.locale, &1.current?}) == [{"de", false}, {"fr", true}]
    end

    test "returns an error, never raises, for urls or options it cannot use" do
      for {urls, options} <- [
            {[en: "/en"], []},
            {nil, []},
            {%{"not a locale!" => "/x"}, []},
            {%{"en" => 42}, []},
            {%{"en" => "/en"}, [current: "not a locale!"]},
            {%{"en" => "/en"}, %{}}
          ] do
        assert {:error, %{__exception__: true}} = LanguageSwitcher.links(urls, options),
               inspect({urls, options})
      end
    end
  end

  describe "language_switcher/1" do
    test "renders a nav of links with hreflang, lang, dir and aria-current" do
      assigns = %{urls: @urls}

      html =
        rendered_to_string(~H"""
        <LanguageSwitcher.language_switcher urls={@urls} current="ar" label="Language" class="switcher" />
        """)

      document = LazyHTML.from_fragment(html)

      attribute = fn selector, name ->
        document |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
      end

      assert attribute.("nav", "aria-label") == ["Language"]
      assert attribute.("nav", "class") == ["switcher"]

      # In Arabic's collation Arabic script comes first.
      assert attribute.("a", "lang") == ["ar", "en", "fr", "ja"]
      assert attribute.("a", "hreflang") == ["ar", "en", "fr", "ja"]
      assert attribute.("a", "dir") == ["rtl", "ltr", "ltr", "ltr"]
      assert attribute.(~s(a[lang="fr"]), "href") == ["/fr/a-propos"]
      assert attribute.("a[aria-current]", "lang") == ["ar"]
      assert attribute.("a[aria-current]", "aria-current") == ["page"]
      refute html =~ "x-default"
    end

    test "links with navigate for a live navigation" do
      assigns = %{urls: %{"en" => "/en", "fr" => "/fr"}}

      html = rendered_to_string(~H|<LanguageSwitcher.language_switcher urls={@urls} navigate />|)

      assert html =~ ~s(data-phx-link="redirect")
      assert html =~ ~s(href="/fr")
    end

    test "logs urls it cannot use and renders nothing" do
      assigns = %{urls: %{"en" => 42}}

      log =
        capture_log(fn ->
          send(
            self(),
            {:html, rendered_to_string(~H|<LanguageSwitcher.language_switcher urls={@urls} />|)}
          )
        end)

      assert_received {:html, ""}
      assert log =~ "Localize.HTML.LanguageSwitcher.language_switcher/1"
    end
  end
end
