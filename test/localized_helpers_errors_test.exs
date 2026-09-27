defmodule Localize.LocalizedHelpersErrorsTest do
  use ExUnit.Case, async: false

  alias MyApp.Router.LocalizedHelpers, as: Helpers

  setup do
    Localize.put_locale(:en)
    :ok
  end

  describe "localized helper errors" do
    test "an unknown action lists the supported actions" do
      # Raised by the Phoenix helper the localized helper delegates to.
      assert_raise ArgumentError, ~r/no action :nope for .*page_en_path.*supported/s, fn ->
        Helpers.page_path(%Plug.Conn{}, :nope, 1)
      end
    end

    test "a locale without a clause for the helper names the locale" do
      # The `chap` routes are localized for :fr only.
      assert_raise ArgumentError, ~r/for locale/, fn ->
        Helpers.chap_path(%Plug.Conn{}, :show, 1)
      end
    end

    test "params that are not a keyword list or map describe the expected call" do
      assert_raise ArgumentError, ~r/called with invalid params/, fn ->
        Helpers.page_path(%Plug.Conn{}, :show, 1, "page=5")
      end
    end
  end

  describe "hreflang_links/1" do
    test "renders no links for nil or anything that is not a map" do
      for url_map <- [nil, [], "x", 42] do
        assert Helpers.hreflang_links(url_map) == {:safe, []}
      end
    end
  end
end
