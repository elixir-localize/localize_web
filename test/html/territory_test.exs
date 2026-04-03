defmodule Localize.HTML.Territory.Test do
  use ExUnit.Case

  import Phoenix.HTML, only: [safe_to_string: 1]

  describe "territory_select/3" do
    test "with selected territory" do
      string =
        safe_to_string(
          Localize.HTML.Territory.select(
            :my_form,
            :territory,
            territories: [:US, :AU, :HK],
            selected: :AU
          )
        )

      assert string =~ ~s(<select)
      assert string =~ ~s(name="my_form[territory]")
      assert string =~ ~s(value="AU")
      assert string =~ ~s(value="HK")
      assert string =~ ~s(value="US")
      assert string =~ "Australia"
      assert string =~ "selected"
    end

    test "with selected territory and short names" do
      string =
        safe_to_string(
          Localize.HTML.Territory.select(
            :my_form,
            :territory,
            territories: [:US, :AU, :HK],
            selected: :AU,
            style: :short
          )
        )

      assert string =~ ~s(value="AU")
      assert string =~ ~s(value="HK")
      assert string =~ ~s(value="US")
      # Short name for US should be "US" not "United States"
      assert string =~ "US"
    end

    test "with locale" do
      string =
        safe_to_string(
          Localize.HTML.Territory.select(
            :my_form,
            :territory,
            territories: [:US, :AU],
            selected: :IT,
            locale: "th"
          )
        )

      assert string =~ ~s(value="US")
      assert string =~ ~s(value="AU")
      assert string =~ ~s(value="IT")
      # Thai territory names
      assert string =~ "สหรัฐอเมริกา" or string =~ "US"
    end

    test "with locale and custom collator" do
      # Custom collator that sorts territories by name using Localize.Collation
      collator = fn territories ->
        Enum.sort_by(territories, & &1.name, fn a, b ->
          Localize.Collation.compare(a, b) != :gt
        end)
      end

      string =
        safe_to_string(
          Localize.HTML.Territory.select(
            :my_form,
            :territory,
            territories: [:US, :AU],
            selected: :IT,
            locale: "th",
            collator: collator
          )
        )

      assert string =~ ~s(value="US")
      assert string =~ ~s(value="AU")
      assert string =~ ~s(value="IT")
    end
  end

  describe "territory_options/1" do
    test "with selected territory" do
      options =
        Localize.HTML.Territory.territory_options(
          territories: [:US, :AU, :HK],
          selected: :AU
        )

      assert is_list(options)
      assert length(options) == 3

      codes = Enum.map(options, fn {_text, code} -> code end)
      assert :AU in codes
      assert :HK in codes
      assert :US in codes
    end
  end
end
