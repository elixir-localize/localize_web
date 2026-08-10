defmodule Localize.HTML.SubdivisionTest do
  use ExUnit.Case, async: true

  alias Localize.HTML.Subdivision

  doctest Localize.HTML.Subdivision

  describe "subdivision_options/1" do
    test "returns the subdivisions of a territory, stripped of the territory prefix" do
      options = Subdivision.subdivision_options(territory: :US)

      assert length(options) == 57
      assert {"California", "ca"} in options
      assert {"New York", "ny"} in options
      assert {"Texas", "tx"} in options
    end

    test "works for territories whose codes are not two letters" do
      # CLDR subdivision codes are the territory plus the ISO 3166-2 code,
      # which is one to three characters depending on the territory.
      assert {"England", "eng"} in Subdivision.subdivision_options(territory: :GB)
      assert {"Alberta", "ab"} in Subdivision.subdivision_options(territory: :CA)
      assert {"New South Wales", "nsw"} in Subdivision.subdivision_options(territory: :AU)
    end

    test "every subdivision of every territory strips to a non-empty code" do
      # The strip must never truncate a code to nothing, and re-prefixing the
      # stripped code must reproduce the CLDR code exactly. Checked across the
      # whole inventory rather than a sample, because one bad code would
      # silently produce an unusable option value.
      #
      # Note a stripped code may legitimately equal its own prefix: Belize's
      # `bzbz` is the Belize District, and strips to `bz`.
      for territory <- Localize.Territory.individual_territories(),
          prefix = territory |> to_string() |> String.downcase(),
          stripped = Subdivision.subdivision_options(territory: territory),
          full = Subdivision.subdivision_options(territory: territory, full_codes: true),
          {{_name, code}, {_same_name, full_code}} <- Enum.zip(stripped, full) do
        assert code != ""
        assert prefix <> code == to_string(full_code)
      end
    end

    test ":full_codes keeps the CLDR code" do
      options = Subdivision.subdivision_options(territory: :US, full_codes: true)

      assert {"California", :usca} in options
      refute {"California", "ca"} in options
    end

    test "a territory with no subdivisions returns an empty list" do
      # :XX is a valid user-assigned territory code with no subdivisions —
      # an empty list, not an error.
      assert Subdivision.subdivision_options(territory: :XX) == []
    end

    test "an invalid territory returns an error" do
      assert {:error, _} = Subdivision.subdivision_options(territory: :ZZZZ)
    end

    test "a missing territory returns an error rather than every subdivision" do
      assert {:error, _} = Subdivision.subdivision_options([])
    end
  end

  describe "localized names" do
    test "names are returned in the requested locale" do
      french = Subdivision.subdivision_options(territory: :US, locale: :fr)

      assert {"Californie", "ca"} in french
    end

    test "names absent from CLDR's subdivision data fall back to the territory name" do
      # Six US codes — American Samoa, Guam, Northern Mariana Islands, Puerto
      # Rico, US Outlying Islands and the US Virgin Islands — have no
      # subdivision name in any locale, because CLDR models them as
      # territories with their own ISO 3166-1 codes. Without the fallback
      # these render as bare codes.
      english = Subdivision.subdivision_options(territory: :US, locale: :en)

      assert {"Puerto Rico", "pr"} in english
      assert {"Guam", "gu"} in english
      assert {"American Samoa", "as"} in english
    end

    test "the territory fallback is itself localized" do
      french = Subdivision.subdivision_options(territory: :US, locale: :fr)

      assert {"Porto Rico", "pr"} in french
      assert {"Samoa américaines", "as"} in french
    end

    test "no option is left as a bare CLDR code" do
      # Every option should carry a human-readable name; a value that still
      # looks like `usxx` means the fallback chain fell through.
      for territory <- [:US, :CA, :FR, :GB, :AU, :DE, :JP],
          {name, _code} <- Subdivision.subdivision_options(territory: territory) do
        refute name =~ ~r/^#{String.downcase(to_string(territory))}[a-z0-9]+$/
      end
    end
  end

  describe "options" do
    test "an invalid locale returns an error" do
      assert {:error, _} = Subdivision.subdivision_options(territory: :US, locale: "nonsense")
    end

    test "a custom mapper shapes the option" do
      options =
        Subdivision.subdivision_options(
          territory: :US,
          mapper: &{String.upcase(&1.name), &1.full_code}
        )

      assert {"CALIFORNIA", :usca} in options
    end

    test "a custom collator orders the options" do
      options =
        Subdivision.subdivision_options(
          territory: :US,
          collator: &Enum.sort_by(&1, fn subdivision -> subdivision.name end, :desc)
        )

      assert {"Wyoming", "wy"} == hd(options)
    end
  end

  describe "select/3" do
    test "renders a select tag" do
      html =
        :address
        |> Subdivision.select(:state, territory: :US)
        |> Phoenix.HTML.safe_to_string()

      assert html =~ ~s(<select id="address_state" name="address[state]">)
      assert html =~ ~s(<option value="ca">California</option>)
    end

    test "marks the selected subdivision" do
      html =
        :address
        |> Subdivision.select(:state, territory: :US, selected: "ny")
        |> Phoenix.HTML.safe_to_string()

      assert html =~ ~s(<option selected value="ny">New York</option>)
    end

    test "an invalid territory returns an error rather than rendering" do
      assert {:error, _} = Subdivision.select(:address, :state, territory: :ZZZZ)
    end
  end

  describe "the Localize.HTML facade" do
    test "exposes both functions" do
      assert Localize.HTML.subdivision_options(territory: :US) ==
               Subdivision.subdivision_options(territory: :US)

      assert function_exported?(Localize.HTML, :subdivision_select, 3)
    end
  end
end
