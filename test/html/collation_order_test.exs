defmodule Localize.HTML.CollationOrderTest do
  # The HTML helpers sort names by the CLDR collation of the locale they are
  # displayed in, not by their UTF-8 bytes, which put every accented capital
  # after Z: "Ägypten" after "Simbabwe", "Île-de-France" after "La Réunion".
  use ExUnit.Case, async: true

  alias Localize.HTML

  defp values(options) do
    Enum.map(options, &elem(&1, 1))
  end

  test "territories" do
    # Ägypten, Albanien, Österreich, Panama, Simbabwe.
    assert values(
             HTML.Territory.territory_options(locale: :de, territories: [:AT, :PA, :EG, :AL, :ZW])
           ) ==
             [:EG, :AL, :AT, :PA, :ZW]
  end

  test "currencies" do
    # dollar des États-Unis, euro, rand, sucre équatorien, unité de compte européenne.
    assert values(
             HTML.Currency.currency_options(
               locale: :fr,
               currencies: [:EUR, :XEU, :USD, :ZAR, :ECS]
             )
           ) ==
             ["USD", "EUR", "ZAR", "ECS", "XEU"]
  end

  test "units" do
    # mètres, miles, millimètres, yards.
    assert values(HTML.Unit.unit_options(locale: :fr, units: [:meter, :mile, :millimeter, :yard])) ==
             ["meter", "mile", "millimeter", "yard"]
  end

  test "subdivisions" do
    # Hauts-de-France, Île Clipperton, Île-de-France, then La Réunion.
    codes = values(HTML.Subdivision.subdivision_options(territory: :FR, locale: :fr))
    position = fn code -> Enum.find_index(codes, &(&1 == code)) end

    assert position.("hdf") < position.("cp")
    assert position.("cp") < position.("idf")
    assert position.("idf") < position.("lre")
  end

  test "locales" do
    assert values(HTML.Locale.locale_options(locale: :de, locales: [:fr, :en, :ar, :ja, :de])) ==
             ["ar", "de", "en", "fr", "ja"]
  end

  describe "the collation" do
    # Japanese orders 漢 before 日本 (JIS order); the root orders them the
    # other way.
    test "is the display locale's" do
      names = ["日本", "漢"]

      assert HTML.Options.collate(names, & &1, :ja) == ["漢", "日本"]
      assert HTML.Options.collate(names, & &1, :und) == ["日本", "漢"]
    end

    test "is the current locale's for the :identity display" do
      {:ok, _locale} = Localize.put_locale(:ja)

      assert HTML.Options.collate(["日本", "漢"], & &1, :identity) == ["漢", "日本"]
    end

    test "sorts a name that has no sort key, or a locale with no collation, without failing" do
      items = [%{name: "b"}, %{name: nil}, %{name: "a"}]

      assert HTML.Options.collate(items, & &1.name, :fr) == [
               %{name: nil},
               %{name: "a"},
               %{name: "b"}
             ]

      assert HTML.Options.collate(["b", "a"], & &1, "not a locale!") == ["a", "b"]
    end

    test "a collator the caller gives is used as it is" do
      # By name in descending byte order, Österreich before Ägypten; the
      # default puts Ägypten first.
      descending = &Enum.sort_by(&1, fn territory -> territory.name end, :desc)
      options = [locale: :de, territories: [:AT, :EG]]

      assert values(HTML.Territory.territory_options(options)) == [:EG, :AT]

      assert values(HTML.Territory.territory_options([{:collator, descending} | options])) == [
               :AT,
               :EG
             ]

      assert {:error, %Localize.InvalidValueError{}} =
               HTML.Territory.territory_options([{:collator, :default_order} | options])
    end
  end
end
