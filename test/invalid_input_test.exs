defmodule Localize.InvalidInputTest do
  # Functions that take request or session data must return an error or
  # nil for any input, never raise.
  use ExUnit.Case, async: true

  @garbage [nil, "", :"", %{}, 42, [1], {:a}, String.duplicate("x", 5000)]

  describe "Localize.AcceptLanguage" do
    test "tokenize/1 returns no tags for a header that is not a string" do
      for header <- @garbage, not is_binary(header) do
        assert Localize.AcceptLanguage.tokenize(header) == []
      end
    end

    test "parse/1 and best_match/1 return an error for a header that is not a string" do
      for header <- @garbage, not is_binary(header) do
        assert {:error, %Localize.InvalidValueError{}} = Localize.AcceptLanguage.parse(header)

        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.AcceptLanguage.best_match(header)
      end
    end

    test "malformed headers do not raise" do
      for header <- ["", "*", ",,;;", "en;q=abc", "en-US;q=2", String.duplicate("x", 5000)] do
        assert {:ok, _results} = Localize.AcceptLanguage.parse(header)
        assert {_ok_or_error, _value} = Localize.AcceptLanguage.best_match(header)
      end
    end
  end

  describe "Localize.Plug.AcceptLanguage" do
    import ExUnit.CaptureLog

    test "best_match/2 returns nil for a header that matches nothing or is not a string" do
      options = Localize.Plug.AcceptLanguage.init(no_match_log_level: nil)

      capture_log(fn ->
        for header <- @garbage ++ ["*", "zz-ZZ"] do
          assert Localize.Plug.AcceptLanguage.best_match(header, options) == nil
        end
      end)
    end

    test "best_match/2 logs a header that is not a string" do
      options = Localize.Plug.AcceptLanguage.init([])

      assert capture_log(fn -> Localize.Plug.AcceptLanguage.best_match(42, options) end) =~
               "error parsing accept-language header 42"
    end
  end

  describe "locale getters" do
    test "get_locale/1 returns nil for anything that is not a conn" do
      for conn <- @garbage do
        assert Localize.Plug.PutLocale.get_locale(conn) == nil
        assert Localize.Plug.AcceptLanguage.get_locale(conn) == nil
      end
    end

    test "locale_from_host/1 returns nil for a host that is not a string" do
      for host <- @garbage, not is_binary(host) do
        assert Localize.Plug.PutLocale.locale_from_host(host) == nil
      end
    end
  end

  describe "Localize.Plug.put_locale_from_session/2" do
    @session %{"localize_locale" => "fr"}

    test "returns an error for a stored locale that is not valid" do
      for locale <- @garbage, locale != nil do
        assert {:error, %{__exception__: true}} =
                 Localize.Plug.put_locale_from_session(%{"localize_locale" => locale})
      end
    end

    test "returns an error for options that are not a keyword list" do
      for options <- [nil, %{}, 42, [1], "x"] do
        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Plug.put_locale_from_session(@session, options)
      end
    end

    test "returns an error for a :gettext that is not a Gettext backend" do
      for gettext <- [:not_a_module, Enum, 42, "MyApp.Gettext", [MyApp.Gettext, Enum]] do
        assert {:error, %Localize.InvalidValueError{}} =
                 Localize.Plug.put_locale_from_session(@session, gettext: gettext)
      end
    end

    test "sets the locale for each Gettext backend" do
      assert {:ok, %{cldr_locale_id: :fr}} =
               Localize.Plug.put_locale_from_session(@session, gettext: [MyApp.Gettext])

      assert Gettext.get_locale(MyApp.Gettext) == "fr"
    end
  end
end
