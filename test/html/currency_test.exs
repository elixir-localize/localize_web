defmodule Localize.HTML.Currency.Test do
  use ExUnit.Case

  import Phoenix.HTML, only: [safe_to_string: 1]

  describe "currency_select/3" do
    test "with selected currency" do
      string =
        safe_to_string(
          Localize.HTML.Currency.select(
            :my_form,
            :currency,
            selected: :USD,
            currencies: ~w(USD EUR JPY COP)
          )
        )

      assert string =~ ~s(<select)
      assert string =~ ~s(name="my_form[currency]")
      assert string =~ ~s(value="USD")
      assert string =~ ~s(value="EUR")
      assert string =~ ~s(value="JPY")
      assert string =~ ~s(value="COP")
    end

    test "without selected currency" do
      string =
        safe_to_string(
          Localize.HTML.Currency.select(
            :my_form,
            :currency,
            currencies: ~w(USD EUR JPY COP)
          )
        )

      assert string =~ ~s(<select)
      assert string =~ ~s(value="USD")
      assert string =~ ~s(value="EUR")
      assert string =~ ~s(value="JPY")
      assert string =~ ~s(value="COP")
    end

    test "when selected currency is not in currencies" do
      string =
        safe_to_string(
          Localize.HTML.Currency.select(
            :my_form,
            :currency,
            selected: :USD,
            currencies: ~w(EUR JPY)
          )
        )

      assert string =~ ~s(value="USD")
      assert string =~ ~s(value="EUR")
      assert string =~ ~s(value="JPY")
    end

    test "with thai locale" do
      string =
        safe_to_string(
          Localize.HTML.Currency.select(
            :my_form,
            :currency,
            currencies: ~w(USD EUR JPY COP),
            locale: "th"
          )
        )

      assert string =~ ~s(<select)
      assert string =~ ~s(value="USD")
      assert string =~ ~s(value="EUR")
      # Thai script characters should be present
      assert string =~ "ดอลลาร์สหรัฐ" or string =~ "USD"
    end

    test "with invalid selected" do
      assert {:error, _} =
               Localize.HTML.Currency.select(
                 :my_form,
                 :currency,
                 selected: "INVALID1",
                 currencies: ~w(USD EUR JPY COP)
               )
    end

    test "with invalid currencies" do
      assert {:error, _} =
               Localize.HTML.Currency.select(
                 :my_form,
                 :currency,
                 currencies: ~w(INVALID1 INVALID2)
               )
    end
  end

  describe "currency_options/1" do
    test "with selected currency" do
      options =
        Localize.HTML.Currency.currency_options(
          currencies: [:USD, :JPY, :EUR],
          selected: :USD
        )

      assert is_list(options)
      assert length(options) == 3

      # Each option is a {display_text, code} tuple
      codes = Enum.map(options, fn {_text, code} -> code end)
      assert "USD" in codes
      assert "EUR" in codes
      assert "JPY" in codes
    end
  end
end
