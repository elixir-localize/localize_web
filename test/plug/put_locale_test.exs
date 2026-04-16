defmodule Localize.Plug.PutLocaleTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Localize.Plug.PutLocale

  @default_locale Localize.default_locale()

  describe "init/1" do
    test "default options" do
      options = PutLocale.init([])
      assert options[:from] == [:session, :accept_language, :query, :path, :route]
      assert options[:param] == "locale"
      assert options[:gettext] == []
      # Default is deferred to request time to avoid loading CLDR data
      # at compile time. The sentinel is resolved in call/2.
      assert options[:default] == :__localize_default__
    end

    test "accepts valid :from option" do
      options = PutLocale.init(from: [:query, :path])
      assert options[:from] == [:query, :path]
    end

    test "accepts a single atom for :from" do
      options = PutLocale.init(from: :query)
      assert options[:from] == [:query]
    end

    test "raises on invalid :from option" do
      assert_raise ArgumentError, ~r/Invalid :from option/, fn ->
        PutLocale.init(from: [:invalid_source])
      end
    end

    test "raises on invalid :param option" do
      assert_raise ArgumentError, ~r/Invalid :param/, fn ->
        PutLocale.init(param: 123)
      end
    end

    test "accepts MFA tuple in :from" do
      options = PutLocale.init(from: [{MyModule, :get_locale}])
      assert options[:from] == [{MyModule, :get_locale}]
    end

    test "accepts MFA with extra args in :from" do
      options = PutLocale.init(from: [{MyModule, :get_locale, [:fred]}])
      assert options[:from] == [{MyModule, :get_locale, [:fred]}]
    end

    test "accepts :default as :none" do
      options = PutLocale.init(default: :none)
      assert options[:default] == nil
    end

    test "accepts :default as a locale string" do
      options = PutLocale.init(default: "fr")
      assert %Localize.LanguageTag{cldr_locale_id: :fr} = options[:default]
    end

    test "accepts :default as an MFA tuple" do
      options = PutLocale.init(default: {MyModule, :get_locale})
      assert options[:default] == {MyModule, :get_locale, []}
    end

    test "raises on invalid :default locale" do
      assert_raise Localize.InvalidLocaleError, fn ->
        PutLocale.init(default: "!!!")
      end
    end

    test "accepts a single gettext backend" do
      options = PutLocale.init(gettext: MyApp.Gettext)
      assert options[:gettext] == [MyApp.Gettext]
    end

    test "accepts a list of gettext backends" do
      options = PutLocale.init(gettext: [MyApp.Gettext])
      assert options[:gettext] == [MyApp.Gettext]
    end

    test "defaults gettext to empty list" do
      options = PutLocale.init([])
      assert options[:gettext] == []
    end
  end

  describe "session_key/0" do
    test "returns the session key" do
      assert PutLocale.session_key() == "localize_locale"
    end
  end

  describe "call/2 - set locale from query param" do
    test "sets locale from query parameter" do
      options = PutLocale.init(from: [:query])

      conn =
        :get
        |> conn("/?locale=fr")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :fr
      assert locale.language == :fr
    end

    test "uses custom param name from query" do
      options = PutLocale.init(from: [:query], param: "lang")

      conn =
        :get
        |> conn("/?lang=de")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert locale.cldr_locale_id == :de
      assert locale.language == :de
    end

    test "falls back to default when no query param is present" do
      options = PutLocale.init(from: [:query])

      conn =
        :get
        |> conn("/")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == @default_locale.cldr_locale_id
    end
  end

  describe "call/2 - set locale from body param" do
    test "sets locale from body parameter" do
      options = PutLocale.init(from: [:body])

      conn =
        :post
        |> conn("/", %{"locale" => "de"})
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :de
      assert locale.language == :de
    end
  end

  describe "call/2 - set locale from cookie" do
    test "sets locale from cookie" do
      options = PutLocale.init(from: [:cookie])

      conn =
        :get
        |> conn("/")
        |> put_req_cookie("locale", "fr")
        |> fetch_cookies()
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :fr
      assert locale.language == :fr
    end

    test "falls back to default when cookie is not present" do
      options = PutLocale.init(from: [:cookie])

      conn =
        :get
        |> conn("/")
        |> fetch_cookies()
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert locale.cldr_locale_id == @default_locale.cldr_locale_id
    end
  end

  describe "call/2 - set locale from accept-language header" do
    test "sets locale from accept-language header" do
      options = PutLocale.init(from: [:accept_language])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "fr-CH, fr;q=0.9, en;q=0.8")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.language == :fr
    end

    @tag :capture_log
    test "falls back to default when accept-language has no valid locale" do
      options = PutLocale.init(from: [:accept_language])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "!!!")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == @default_locale.cldr_locale_id
    end

    test "selects highest quality matching locale" do
      options = PutLocale.init(from: [:accept_language])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "de;q=0.7, fr;q=0.9, en;q=0.8")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert locale.language == :fr
    end
  end

  describe "call/2 - set locale from host" do
    test "sets locale from host TLD" do
      options = PutLocale.init(from: [:host])

      conn =
        :get
        |> conn("http://example.de/")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.territory == :DE
    end

    test "sets locale from .au TLD" do
      options = PutLocale.init(from: [:host])

      conn =
        :get
        |> conn("http://example.au/")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.territory == :AU
    end

    test "does not set locale from generic TLD" do
      options = PutLocale.init(from: [:host])

      conn =
        :get
        |> conn("http://example.com/")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      # Falls back to default since .com is generic
      assert locale.cldr_locale_id == @default_locale.cldr_locale_id
    end
  end

  describe "call/2 - set locale from MFA" do
    test "sets locale from {Module, function}" do
      options = PutLocale.init(from: [{MyModule, :get_locale}])

      conn =
        :get
        |> conn("/")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :fr
      assert locale.language == :fr
    end

    test "sets locale from {Module, function, args}" do
      options = PutLocale.init(from: [{MyModule, :get_locale, [:fred]}])

      conn =
        :get
        |> conn("/")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :fr
      assert locale.language == :fr
    end
  end

  describe "call/2 - priority ordering" do
    test "earlier sources in :from take priority" do
      options = PutLocale.init(from: [:query, :accept_language])

      conn =
        :get
        |> conn("/?locale=de")
        |> put_req_header("accept-language", "fr")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert locale.cldr_locale_id == :de
    end

    test "falls through to next source when first has no locale" do
      options = PutLocale.init(from: [:query, :accept_language])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "fr")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert locale.cldr_locale_id == :fr
    end
  end

  describe "call/2 - default locale" do
    test "uses default locale when no source provides one" do
      options = PutLocale.init(from: [:query])

      conn =
        :get
        |> conn("/")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == @default_locale.cldr_locale_id
    end

    test "does not set locale when default is :none and no locale found" do
      options = PutLocale.init(from: [:query], default: :none)

      conn =
        :get
        |> conn("/")
        |> PutLocale.call(options)

      refute Map.has_key?(conn.private, :localize_locale)
    end

    test "uses MFA default" do
      options =
        PutLocale.init(
          from: [:query],
          default: {MyModule, :get_locale}
        )

      conn =
        :get
        |> conn("/")
        |> PutLocale.call(options)

      locale = conn.private[:localize_locale]
      assert locale.cldr_locale_id == :fr
    end
  end

  describe "call/2 - sets Localize process locale" do
    test "always sets the Localize process locale" do
      options = PutLocale.init(from: [:query])

      :get
      |> conn("/?locale=de")
      |> PutLocale.call(options)

      process_locale = Localize.get_locale()
      assert %Localize.LanguageTag{} = process_locale
      assert process_locale.cldr_locale_id == :de
    end
  end

  describe "call/2 - sets Gettext locale" do
    test "sets locale on configured gettext backend" do
      options = PutLocale.init(from: [:query], gettext: MyApp.Gettext)

      :get
      |> conn("/?locale=fr")
      |> PutLocale.call(options)

      assert Gettext.get_locale(MyApp.Gettext) == "fr"
    end
  end

  describe "locale_from_host/1" do
    test "returns locale for valid country TLD" do
      {:ok, locale} = PutLocale.locale_from_host("example.de")
      assert locale.territory == :DE
    end

    test "returns locale for .fr TLD" do
      {:ok, locale} = PutLocale.locale_from_host("example.fr")
      assert locale.language == :fr
    end

    test "returns nil for generic TLD" do
      assert PutLocale.locale_from_host("example.com") == nil
    end

    test "returns nil for nil host" do
      assert PutLocale.locale_from_host(nil) == nil
    end
  end

  describe "get_locale/1" do
    test "returns locale from conn" do
      options = PutLocale.init(from: [:query])

      conn =
        :get
        |> conn("/?locale=de")
        |> PutLocale.call(options)

      locale = PutLocale.get_locale(conn)
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :de
    end

    test "returns nil when no locale has been set" do
      test_conn = conn(:get, "/")
      assert PutLocale.get_locale(test_conn) == nil
    end
  end
end
