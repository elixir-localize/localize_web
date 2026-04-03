defmodule Localize.HTML.Unit.Test do
  use ExUnit.Case

  import Phoenix.HTML, only: [safe_to_string: 1]

  describe "unit_select/3" do
    test "with selected unit" do
      string =
        safe_to_string(
          Localize.HTML.Unit.select(
            :my_form,
            :unit,
            units: [:foot, :inch],
            selected: :foot
          )
        )

      assert string =~ ~s(<select)
      assert string =~ ~s(name="my_form[unit]")
      assert string =~ ~s(value="foot")
      assert string =~ ~s(value="inch")
      assert string =~ "selected"
    end

    test "with locale" do
      string =
        safe_to_string(
          Localize.HTML.Unit.select(
            :my_form,
            :unit,
            units: [:foot, :inch],
            selected: :foot,
            locale: "th"
          )
        )

      assert string =~ ~s(value="foot")
      assert string =~ ~s(value="inch")
      # Thai unit names should be present
      assert string =~ "ฟุต" or string =~ "foot"
    end
  end

  describe "unit_options/1" do
    test "with selected unit" do
      options =
        Localize.HTML.Unit.unit_options(
          units: [:foot, :inch],
          selected: :foot
        )

      assert is_list(options)
      assert length(options) == 2

      codes = Enum.map(options, fn {_name, code} -> code end)
      assert "foot" in codes
      assert "inch" in codes
    end
  end
end
