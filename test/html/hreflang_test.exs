defmodule Localize.HTML.HreflangTest do
  use ExUnit.Case, async: true

  doctest Localize.HTML.Hreflang

  alias Localize.HTML.Hreflang

  defp render(alternates, options \\ []) do
    case Hreflang.links(alternates, options) do
      {:ok, safe} -> Phoenix.HTML.safe_to_string(safe)
      other -> other
    end
  end

  describe "locales that real sites get wrong" do
    # Each of these was observed in the hreflang of a major brand while
    # measuring the web. Emitting them verbatim produces markup that every
    # consumer ignores without complaint.
    test "an invented region is an error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Hreflang.links(%{"sq-KS" => "https://example.com/"})

      assert {:error, %Localize.InvalidLocaleError{}} =
               Hreflang.links(%{"es-SP" => "https://example.com/"})
    end

    test "a tag that is not a locale is an error" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Hreflang.links(%{"tc" => "https://example.com/"})
    end

    test "an underscore is canonicalised to a hyphen" do
      # Validation alone does not catch this: Localize accepts the POSIX
      # spelling, but BCP 47 and therefore hreflang require a hyphen.
      assert render(%{"es_MX" => "https://example.com/mx/"}) =~ ~s|hreflang="es-MX"|
      assert render(%{"pt_BR" => "https://example.com/br/"}) =~ ~s|hreflang="pt-BR"|
    end

    test "casing is canonicalised" do
      assert render(%{"en-us" => "https://example.com/"}) =~ ~s|hreflang="en-US"|
    end

    test "canonicalisation can be turned off" do
      assert render(%{"en-us" => "https://example.com/"}, canonicalize: false) =~
               ~s|hreflang="en-us"|
    end
  end

  describe "urls" do
    test "a relative url is an error" do
      assert {:error, %Localize.RelativeUrlError{}} = Hreflang.links(%{"de" => "/de/"})
      assert {:error, %Localize.RelativeUrlError{}} = Hreflang.links(%{"de" => "example.com/de"})
    end

    test "the error names the url and the locale" do
      {:error, error} = Hreflang.links(%{"de" => "/de/"})

      assert error.url == "/de/"
      assert error.locale == "de"
      assert Exception.message(error) =~ "not fully qualified"
    end

    test "http and https are both accepted" do
      assert render(%{"de" => "http://example.com/de/"}) =~ ~s|href="http://example.com/de/"|
      assert render(%{"de" => "https://example.com/de/"}) =~ ~s|href="https://example.com/de/"|
    end
  end

  describe "x-default" do
    test "is emitted verbatim rather than canonicalised" do
      # Localize parses it as a private-use subtag and would render it as
      # "-x-default", which is not what the hreflang spec reserves.
      assert render(%{"x-default" => "https://example.com/"}) =~ ~s|hreflang="x-default"|
    end

    test "is ordered after the alternatives" do
      html =
        render(%{
          "x-default" => "https://example.com/",
          "de" => "https://example.com/de/",
          "en" => "https://example.com/en/"
        })

      # x-default is the fallback, so it belongs after the alternatives it
      # falls back from.
      positions =
        for locale <- ~w(de en x-default) do
          {locale, :binary.match(html, ~s|hreflang="#{locale}"|) |> elem(0)}
        end

      assert positions == Enum.sort_by(positions, &elem(&1, 1))
      assert List.last(positions) |> elem(0) == "x-default"
    end

    test "its url is still required to be absolute" do
      assert {:error, %Localize.RelativeUrlError{}} = Hreflang.links(%{"x-default" => "/"})
    end
  end

  describe "rendering" do
    test "nil produces no tags" do
      assert {:ok, {:safe, []}} = Hreflang.links(nil)
    end

    test "an empty map produces no tags" do
      assert render(%{}) == ""
    end

    test "output is stable across calls" do
      alternates = %{
        "fr" => "https://example.com/fr/",
        "de" => "https://example.com/de/",
        "en" => "https://example.com/"
      }

      assert render(alternates) == render(alternates)
    end

    test "every locale is annotated, including the current one" do
      # Search engines require the set to be self-referential.
      html =
        render(%{
          "en" => "https://example.com/",
          "de" => "https://example.com/de/",
          "fr" => "https://example.com/fr/"
        })

      for locale <- ~w(en de fr) do
        assert html =~ ~s|hreflang="#{locale}"|
      end

      assert html =~ ~s|rel="alternate"|
    end

    test "the first bad entry stops the render" do
      assert {:error, %Localize.InvalidLocaleError{}} =
               Hreflang.links(%{"de" => "https://example.com/de/", "es-SP" => "https://x.test/"})
    end
  end
end
