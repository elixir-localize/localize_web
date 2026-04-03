defmodule LocalizeWebTest do
  use ExUnit.Case

  test "accept_language tokenize" do
    tokens = Localize.AcceptLanguage.tokenize("en-US,en;q=0.9,fr;q=0.8")
    assert [{1.0, "en-us"}, {0.9, "en"}, {0.8, "fr"}] = tokens
  end

  test "accept_language best_match finds valid locale" do
    assert {:ok, %Localize.LanguageTag{}} = Localize.AcceptLanguage.best_match("en-US,fr;q=0.8")
  end

  test "accept_language best_match returns error for wildcard-only header" do
    assert {:error, _} = Localize.AcceptLanguage.best_match("*")
  end

  test "session key" do
    assert Localize.Plug.PutLocale.session_key() == "localize_locale"
  end

  test "PutLocale.get_locale returns nil when no locale set" do
    conn = %Plug.Conn{private: %{}}
    assert Localize.Plug.PutLocale.get_locale(conn) == nil
  end

  test "PutLocale.get_locale returns locale when set" do
    {:ok, locale} = Localize.validate_locale(:en)
    conn = %Plug.Conn{private: %{localize_locale: locale}}
    assert Localize.Plug.PutLocale.get_locale(conn) == locale
  end

  test "PutSession init with default options" do
    assert %{as: :string} = Localize.Plug.PutSession.init([])
  end

  test "PutSession init with language_tag option" do
    assert %{as: :language_tag} = Localize.Plug.PutSession.init(as: :language_tag)
  end

  test "locale_from_host returns nil for generic TLDs" do
    assert Localize.Plug.PutLocale.locale_from_host("example.com") == nil
    assert Localize.Plug.PutLocale.locale_from_host("example.org") == nil
  end

  test "locale_from_host resolves country TLDs" do
    result = Localize.Plug.PutLocale.locale_from_host("example.de")
    assert {:ok, %Localize.LanguageTag{territory: :DE}} = result
  end

  test "locale_from_host returns nil for nil" do
    assert Localize.Plug.PutLocale.locale_from_host(nil) == nil
  end

  test "put_locale_from_session returns error when no locale in session" do
    assert {:error, _} = Localize.Plug.put_locale_from_session(%{})
  end

  test "Phoenix.HTML.Safe protocol for Localize.LanguageTag" do
    {:ok, tag} = Localize.validate_locale(:en)
    assert is_binary(Phoenix.HTML.Safe.to_iodata(tag))
  end
end
