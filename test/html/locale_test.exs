defmodule Localize.HTML.Locale.Test do
  use ExUnit.Case

  import Phoenix.HTML, only: [safe_to_string: 1]

  describe "locale_select/3" do
    test "with selected locale" do
      string =
        safe_to_string(
          Localize.HTML.Locale.select(
            :my_form,
            :locale,
            selected: "en",
            locales: ~w(en ja ar zh-Hant zh-Hans)
          )
        )

      assert string =~ ~s(<select)
      assert string =~ ~s(name="my_form[locale]")
      assert string =~ "Arabic"
      assert string =~ "English"
      assert string =~ "Japanese"
      assert string =~ "selected"
    end
  end

  describe "locale_options/1" do
    test "with selected locale" do
      options =
        Localize.HTML.Locale.locale_options(
          locales: [:en, :ja, :ar],
          selected: :en
        )

      assert is_list(options)
      assert length(options) == 3

      display_names = Enum.map(options, fn {name, _locale} -> name end)
      assert Enum.any?(display_names, &String.starts_with?(&1, "Arabic"))
      assert Enum.any?(display_names, &String.starts_with?(&1, "English"))
      assert Enum.any?(display_names, &String.starts_with?(&1, "Japanese"))
    end
  end
end
