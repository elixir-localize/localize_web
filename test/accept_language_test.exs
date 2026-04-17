defmodule Localize.AcceptLanguageTest do
  use ExUnit.Case, async: true

  alias Localize.AcceptLanguage

  describe "tokenize/1" do
    test "simple single language" do
      assert [{1.0, "en"}] = AcceptLanguage.tokenize("en")
    end

    test "single language with region" do
      assert [{1.0, "en-us"}] = AcceptLanguage.tokenize("en-US")
    end

    test "multiple languages with quality values" do
      tokens = AcceptLanguage.tokenize("en-US,en;q=0.9,fr;q=0.8")
      assert [{1.0, "en-us"}, {0.9, "en"}, {0.8, "fr"}] = tokens
    end

    test "explicit q=1.0 treated same as implicit" do
      tokens = AcceptLanguage.tokenize("de;q=1.0, en;q=0.5")
      assert [{1.0, "de"}, {0.5, "en"}] = tokens
    end

    test "two-digit quality precision" do
      tokens = AcceptLanguage.tokenize("en-US;q=0.95,fr;q=0.85")
      assert [{0.95, "en-us"}, {0.85, "fr"}] = tokens
    end

    test "wildcard is filtered out" do
      tokens = AcceptLanguage.tokenize("fr-CH, fr;q=0.9, en;q=0.8, *;q=0.5")
      assert [{1.0, "fr-ch"}, {0.9, "fr"}, {0.8, "en"}] = tokens
    end

    test "wildcard-only header returns empty list" do
      assert [] = AcceptLanguage.tokenize("*")
    end

    test "wildcard with q=0 is filtered out" do
      tokens = AcceptLanguage.tokenize("fr;q=0.9, *;q=0")
      assert [{0.9, "fr"}] = tokens
    end

    test "spaces after commas and around values" do
      tokens = AcceptLanguage.tokenize("de, en;q=0.5")
      assert [{1.0, "de"}, {0.5, "en"}] = tokens
    end

    test "spaces everywhere" do
      tokens = AcceptLanguage.tokenize("de-de, de;q=0.75, en-us;q=0.50, en;q=0.25")
      assert [{1.0, "de-de"}, {0.75, "de"}, {0.50, "en-us"}, {0.25, "en"}] = tokens
    end

    test "multiple languages at same quality sorted by quality descending" do
      tokens = AcceptLanguage.tokenize("en;q=0.5, fr;q=0.5, de;q=0.5")
      assert Enum.all?(tokens, fn {q, _} -> q == 0.5 end)
      assert length(tokens) == 3
    end

    test "many languages with granular quality values" do
      header =
        "en,ja;q=0.9,fr;q=0.8,de;q=0.7,es;q=0.6,it;q=0.5,nl;q=0.4,sv;q=0.3,nb;q=0.2,da;q=0.1"

      tokens = AcceptLanguage.tokenize(header)
      assert length(tokens) == 10
      assert {1.0, "en"} = hd(tokens)
      assert {0.1, "da"} = List.last(tokens)
    end

    test "script subtags preserved" do
      tokens = AcceptLanguage.tokenize("zh-Hans,zh-Hant-HK;q=0.9,sr-Latn;q=0.8")
      assert [{1.0, "zh-hans"}, {0.9, "zh-hant-hk"}, {0.8, "sr-latn"}] = tokens
    end

    test "Norwegian variants" do
      tokens = AcceptLanguage.tokenize("nb,no;q=0.8,nn;q=0.6,en-us;q=0.4,en;q=0.2")
      assert [{1.0, "nb"}, {0.8, "no"}, {0.6, "nn"}, {0.4, "en-us"}, {0.2, "en"}] = tokens
    end

    test "no quality values at all" do
      tokens = AcceptLanguage.tokenize("de,fr,it,en")
      assert Enum.all?(tokens, fn {q, _} -> q == 1.0 end)
      assert length(tokens) == 4
    end

    test "mixed case region subtags are lowercased" do
      tokens = AcceptLanguage.tokenize("zh-CN,en-US;q=0.5")
      assert [{1.0, "zh-cn"}, {0.5, "en-us"}] = tokens
    end

    test "underscore in locale tag (non-standard but common)" do
      tokens = AcceptLanguage.tokenize("en_US, en")
      assert length(tokens) == 2
    end

    test "three-letter language code" do
      tokens = AcceptLanguage.tokenize("ast,es;q=0.9,en;q=0.5")
      assert [{1.0, "ast"}, {0.9, "es"}, {0.5, "en"}] = tokens
    end

    test "numeric region code es-419" do
      tokens = AcceptLanguage.tokenize("es-419,es;q=0.9,en;q=0.8")
      assert [{1.0, "es-419"}, {0.9, "es"}, {0.8, "en"}] = tokens
    end

    test "empty string returns empty list" do
      assert [] = AcceptLanguage.tokenize("")
    end

    test "duplicate language tags with different q values" do
      tokens = AcceptLanguage.tokenize("en-gb,en;q=0.7,en;q=0.3")
      assert length(tokens) == 3
      assert {1.0, "en-gb"} = hd(tokens)
    end

    test "Chrome reduced accept-language (single entry)" do
      assert [{1.0, "en-us"}] = AcceptLanguage.tokenize("en-US")
    end

    test "complex real-world header with many entries" do
      header =
        "es-ES,es;q=0.9,en-US;q=0.8,en;q=0.7,es-MX;q=0.6,es-es;q=0.4,es;q=0.3,en-us;q=0.2,en;q=0.1"

      tokens = AcceptLanguage.tokenize(header)
      assert length(tokens) == 9
      assert {1.0, "es-es"} = hd(tokens)
    end

    test "semicolon-only malformed header does not crash" do
      tokens = AcceptLanguage.tokenize(";")
      assert is_list(tokens)
    end

    test "trailing semicolon on tag does not crash" do
      tokens = AcceptLanguage.tokenize("en;")
      assert is_list(tokens)
    end

    test "duplicate q= parameter on a tag uses the first weight" do
      # Malformed but seen in real-world headers — `q=` appears twice.
      # Per RFC 9110 §5.3 duplicates are invalid; the parser takes the
      # first weight rather than crashing.
      tokens = AcceptLanguage.tokenize("ja-JP,ja;q=0.9;q=0.9,en;q=0.8;q=0.8")
      assert [{1.0, "ja-jp"}, {0.9, "ja"}, {0.8, "en"}] = tokens
    end
  end

  describe "parse/1" do
    test "parses valid languages" do
      {:ok, results} = AcceptLanguage.parse("en-US,fr;q=0.8")
      assert length(results) == 2

      [{1.0, en_result}, {0.8, fr_result}] = results
      assert {:ok, %Localize.LanguageTag{}} = en_result
      assert {:ok, %Localize.LanguageTag{}} = fr_result
    end

    test "marks invalid languages as errors" do
      {:ok, results} = AcceptLanguage.parse("en,!!!")
      assert length(results) == 2

      [{1.0, en_result}, {1.0, invalid_result}] = results
      assert {:ok, %Localize.LanguageTag{}} = en_result
      assert {:error, _} = invalid_result
    end

    test "handles script subtags" do
      {:ok, results} = AcceptLanguage.parse("zh-Hans,en;q=0.5")
      [{1.0, zh_result}, {0.5, en_result}] = results
      assert {:ok, %Localize.LanguageTag{}} = zh_result
      assert {:ok, %Localize.LanguageTag{}} = en_result
    end
  end

  describe "best_match/1" do
    test "returns best matching locale for simple header" do
      assert {:ok, %Localize.LanguageTag{language: :en}} =
               AcceptLanguage.best_match("en-US,fr;q=0.8")
    end

    test "returns best matching locale for complex header" do
      assert {:ok, %Localize.LanguageTag{language: :fr}} =
               AcceptLanguage.best_match("fr-CH, fr;q=0.9, en;q=0.8, de;q=0.7")
    end

    test "selects highest quality match" do
      assert {:ok, %Localize.LanguageTag{language: :fr}} =
               AcceptLanguage.best_match("de;q=0.7, fr;q=0.9, en;q=0.8")
    end

    test "returns error for wildcard-only" do
      assert {:error, _} = AcceptLanguage.best_match("*")
    end

    test "returns error for completely invalid header" do
      assert {:error, _} = AcceptLanguage.best_match("!!!")
    end

    test "skips invalid entries and matches valid ones" do
      assert {:ok, %Localize.LanguageTag{language: :en}} =
               AcceptLanguage.best_match("!!!,en;q=0.5")
    end

    test "handles German from host-style header" do
      assert {:ok, %Localize.LanguageTag{language: :de}} =
               AcceptLanguage.best_match("de-DE,de;q=0.9,en;q=0.5")
    end

    test "handles many languages with falling quality" do
      header = "en,ja;q=0.9,fr;q=0.8,de;q=0.7,es;q=0.6"

      assert {:ok, %Localize.LanguageTag{language: :en}} =
               AcceptLanguage.best_match(header)
    end

    test "handles Norwegian bokmal" do
      assert {:ok, %Localize.LanguageTag{}} =
               AcceptLanguage.best_match("nb,no;q=0.8,en;q=0.5")
    end

    test "handles Chinese simplified" do
      assert {:ok, %Localize.LanguageTag{language: :zh}} =
               AcceptLanguage.best_match("zh-CN,zh;q=0.9,en;q=0.5")
    end

    test "handles Chinese traditional" do
      assert {:ok, %Localize.LanguageTag{language: :zh}} =
               AcceptLanguage.best_match("zh-TW,zh;q=0.9,en;q=0.5")
    end

    test "handles script subtag zh-Hans" do
      assert {:ok, %Localize.LanguageTag{language: :zh}} =
               AcceptLanguage.best_match("zh-Hans,en;q=0.5")
    end

    test "handles French Swiss with fallback chain" do
      assert {:ok, %Localize.LanguageTag{language: :fr}} =
               AcceptLanguage.best_match("fr-CH,fr;q=0.9,en;q=0.8,de;q=0.7")
    end

    test "handles Romanian with English variants" do
      {:ok, locale} = AcceptLanguage.best_match("ro-RO,ro;q=0.8,en-us;q=0.6,en-gb;q=0.4,en;q=0.2")
      assert locale.language == :ro
    end

    test "handles Polish with German and English fallback" do
      {:ok, locale} = AcceptLanguage.best_match("pl,de-DE;q=0.9,de;q=0.8,en;q=0.7")
      assert locale.language == :pl
    end

    test "handles es-419 Latin American Spanish" do
      {:ok, locale} = AcceptLanguage.best_match("es-419,es;q=0.9,en;q=0.8")
      assert locale.language == :es
    end

    test "handles header with low self-rating" do
      {:ok, locale} = AcceptLanguage.best_match("en-us;q=0.5")
      assert locale.language == :en
    end

    test "handles reversed specific/generic ordering" do
      {:ok, locale} = AcceptLanguage.best_match("fr,fr-fr;q=0.8,en-us;q=0.5,en;q=0.3")
      assert locale.language == :fr
    end

    test "handles many entries with duplicates and mixed case" do
      header = "es-ES,es;q=0.9,en-US;q=0.8,en;q=0.7,es-MX;q=0.6"

      {:ok, locale} = AcceptLanguage.best_match(header)
      assert locale.language == :es
    end

    test "handles empty string" do
      assert {:error, _} = AcceptLanguage.best_match("")
    end

    test "handles header with only invalid entries" do
      assert {:error, _} = AcceptLanguage.best_match("!!!,@@@")
    end

    test "returns first valid locale when invalid entries precede valid ones" do
      {:ok, locale} = AcceptLanguage.best_match("xyz-99,en;q=0.5")
      assert locale.language == :en
    end

    test "handles Firefox-style header with many locales" do
      header =
        "en-US,mr-IN;q=0.9,zh-Hans-CN;q=0.8,fr-FR;q=0.7,hi-IN;q=0.6,ur-IN;q=0.5,zh-Hant-TW;q=0.4,ru-RU;q=0.3,bn-BD;q=0.2,uk-UA;q=0.1"

      {:ok, locale} = AcceptLanguage.best_match(header)
      assert locale.language == :en
    end

    test "handles German chain with Norwegian" do
      header = "de-de,de;q=0.8,en-us;q=0.7,en;q=0.5,en-gb;q=0.3,nb;q=0.2"

      {:ok, locale} = AcceptLanguage.best_match(header)
      assert locale.language == :de
    end

    test "handles malformed header with duplicate q= parameters" do
      # Regression: `"ja;q=0.9;q=0.9"` previously crashed with a
      # CaseClauseError because `String.split("ja;q=0.9;q=0.9", ";q=")`
      # yields three elements. Now it uses the first weight.
      assert {:ok, %Localize.LanguageTag{language: :ja}} =
               AcceptLanguage.best_match(" ja-JP,ja;q=0.9;q=0.9,en;q=0.8;q=0.8")
    end
  end
end
