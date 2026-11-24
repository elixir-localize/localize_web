defmodule Localize.Plug.PutLocaleTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Localize.Plug.PutLocale

  doctest Localize.Plug.PutLocale, import: true

  @default_locale Localize.default_locale()

  describe "init/1" do
    test "default options" do
      options = PutLocale.init([])
      assert options[:from] == [:route, :path, :query, :session, :accept_language]
      assert options[:param] == "locale"
      assert options[:gettext] == []
      # Default is deferred to request time to avoid loading CLDR data
      # at compile time. The sentinel is resolved in call/2.
      assert options[:default] == :__localize_default__
      assert options[:vary] == true
    end

    test "accepts true and false for :vary" do
      assert PutLocale.init(vary: true)[:vary] == true
      assert PutLocale.init(vary: false)[:vary] == false
    end

    test "raises on invalid :vary option" do
      for invalid <- [:except_cookie, "false", 0, []] do
        assert_raise ArgumentError, ~r/Invalid :vary/, fn ->
          PutLocale.init(vary: invalid)
        end
      end
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

  describe "call/2 - set locale from the route" do
    # The router stores the tag it validated when it compiled the route, so
    # the plug takes it as it stands.
    test "takes the route's language tag as it stands" do
      {:ok, route_locale} = Localize.validate_locale("fr")
      options = PutLocale.init(from: [:route])

      conn =
        :get
        |> conn("/")
        |> put_private(:localize_locale, route_locale)
        |> PutLocale.call(options)

      assert conn.private[:localize_locale] == route_locale
    end

    test "validates a locale the route stores as a string" do
      options = PutLocale.init(from: [:route])

      conn =
        :get
        |> conn("/")
        |> put_private(:localize_locale, "fr")
        |> PutLocale.call(options)

      assert %Localize.LanguageTag{cldr_locale_id: :fr} = conn.private[:localize_locale]
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

    test "with the default order a query locale wins over the session and accept-language" do
      conn =
        :get
        |> conn("/?locale=fr")
        |> put_req_header("accept-language", "de")
        |> init_test_session(%{PutLocale.session_key() => "ja"})
        |> PutLocale.call(PutLocale.init([]))

      assert conn.private[:localize_locale].cldr_locale_id == :fr
    end

    test "with the default order a route locale wins over the session and accept-language" do
      conn =
        :get
        |> conn("/")
        |> put_private(:localize_locale, "fr")
        |> put_req_header("accept-language", "de")
        |> init_test_session(%{PutLocale.session_key() => "ja"})
        |> PutLocale.call(PutLocale.init([]))

      assert conn.private[:localize_locale].cldr_locale_id == :fr
    end

    test "with the default order the session wins over accept-language" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "de")
        |> init_test_session(%{PutLocale.session_key() => "ja"})
        |> PutLocale.call(PutLocale.init([]))

      assert conn.private[:localize_locale].cldr_locale_id == :ja
    end

    test "with the default order accept-language applies when nothing else is set" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "de")
        |> init_test_session(%{})
        |> PutLocale.call(PutLocale.init([]))

      assert conn.private[:localize_locale].cldr_locale_id == :de
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

  describe "call/2 - Vary response header" do
    defp vary_after(conn, from) do
      conn
      |> PutLocale.call(PutLocale.init(from: from))
      |> get_resp_header("vary")
    end

    test "fr from accept-language sets Vary: accept-language" do
      conn = conn(:get, "/") |> put_req_header("accept-language", "fr")
      assert vary_after(conn, [:query, :accept_language]) == ["accept-language"]
    end

    test "de from the query after an empty cookie sets Vary: cookie only" do
      conn = conn(:get, "/?locale=de") |> fetch_cookies()
      assert vary_after(conn, [:cookie, :query, :accept_language]) == ["cookie"]
    end

    test "the default after an empty cookie and !!! accept-language sets both" do
      conn = conn(:get, "/") |> fetch_cookies() |> put_req_header("accept-language", "!!!")
      assert vary_after(conn, [:cookie, :accept_language]) == ["cookie, accept-language"]
    end

    test "de from the query sets no Vary" do
      conn = conn(:get, "/?locale=de") |> put_req_header("accept-language", "fr")
      assert vary_after(conn, [:query, :accept_language]) == []
    end

    test "session and cookie sources name cookie once" do
      conn =
        conn(:get, "/")
        |> init_test_session(%{})
        |> fetch_cookies()
        |> put_req_header("accept-language", "fr")

      assert vary_after(conn, [:session, :cookie, :accept_language]) ==
               ["cookie, accept-language"]
    end

    test "an existing Vary line is left as it is and a new line is added" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "fr")
        |> put_resp_header("vary", "Accept-Encoding")

      assert vary_after(conn, [:accept_language]) == ["accept-language", "Accept-Encoding"]
    end

    test "several existing Vary lines are all left as they are" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "fr")
        |> prepend_resp_headers([{"vary", "origin"}, {"vary", "accept-encoding"}])

      assert vary_after(conn, [:accept_language]) ==
               ["accept-language", "origin", "accept-encoding"]
    end

    test "an existing Vary: * is left as it is" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "fr")
        |> put_resp_header("vary", "*")

      assert vary_after(conn, [:accept_language]) == ["accept-language", "*"]
    end

    test "nothing is added when no consulted source reads a header" do
      conn =
        conn(:get, "/?locale=de")
        |> put_resp_header("vary", "Accept-Encoding")

      assert vary_after(conn, [:query, :accept_language]) == ["Accept-Encoding"]
    end

    test "vary: true is the default" do
      conn = conn(:get, "/") |> fetch_cookies() |> put_req_header("accept-language", "fr")
      options = PutLocale.init(from: [:cookie, :accept_language], vary: true)

      assert conn |> PutLocale.call(options) |> get_resp_header("vary") ==
               vary_after(conn, [:cookie, :accept_language])
    end

    test "vary: false adds no Vary and still sets the locale" do
      conn = conn(:get, "/") |> fetch_cookies() |> put_req_header("accept-language", "fr")
      options = PutLocale.init(from: [:cookie, :accept_language], vary: false)
      conn = PutLocale.call(conn, options)

      assert get_resp_header(conn, "vary") == []
      assert conn.private[:localize_locale].cldr_locale_id == :fr
    end

    test "vary: false leaves an existing Vary line as it is" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "fr")
        |> put_resp_header("vary", "x-locale")

      options = PutLocale.init(from: [:accept_language], vary: false)

      assert conn |> PutLocale.call(options) |> get_resp_header("vary") == ["x-locale"]
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

    test "returns nil for generic top-level domains of any length" do
      # A country code is two letters; everything longer is generic. The
      # length test matters beyond tidiness: "com" is the ISO alpha-3 code
      # for Comoros and validates as a territory.
      for host <- ~w(example.com example.org example.net example.app
                     example.cloud example.museum example.travel) do
        assert PutLocale.locale_from_host(host) == nil, "#{host} resolved"
      end
    end

    test "returns nil for country-code domains used generically" do
      # Resolving these names a language the reader probably does not speak:
      # .co would be Spanish, .me Serbian, .ly Arabic.
      for host <- ~w(acme.co acme.io acme.ai acme.me acme.tv acme.ly
                     acme.gg acme.sh acme.cc acme.fm acme.ws acme.to
                     acme.nu acme.st) do
        assert PutLocale.locale_from_host(host) == nil, "#{host} resolved"
      end
    end

    test "a caller can reclaim a generically-used domain" do
      assert {:ok, locale} = PutLocale.locale_from_host("example.co", generic_tlds: [])
      assert locale.territory == :CO

      assert {:ok, locale} = PutLocale.locale_from_host("example.me", generic_tlds: ["co"])
      assert locale.territory == :ME
    end

    test "still resolves genuine country-code domains" do
      for {host, territory} <- [
            {"example.de", :DE},
            {"example.fr", :FR},
            {"example.jp", :JP},
            {"example.br", :BR},
            {"shop.example.it", :IT}
          ] do
        assert {:ok, locale} = PutLocale.locale_from_host(host)
        assert locale.territory == territory
      end
    end

    test "ignores non-ASCII and malformed labels rather than guessing" do
      for host <- ["example.\u0440\u0444", "example.", "example", "a.b.c.d"] do
        assert PutLocale.locale_from_host(host) == nil, "#{host} resolved"
      end
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

  describe "get_locale_source/1" do
    defp resolve(path, from, headers \\ []) do
      conn = conn(:get, path)

      headers
      |> Enum.reduce(conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
      |> PutLocale.call(PutLocale.init(from: from))
    end

    test "is the source the locale was found in" do
      from = [:query, :accept_language]
      headers = [{"accept-language", "fr"}]

      assert PutLocale.get_locale_source(resolve("/?locale=de", from, headers)) == :query
      assert PutLocale.get_locale_source(resolve("/", from, headers)) == :accept_language
    end

    test "is the source that had a locale, not one consulted before it" do
      conn =
        resolve("/?locale=zz", [:query, :accept_language], [
          {"accept-language", "fr"}
        ])

      assert PutLocale.get_locale(conn).cldr_locale_id == :fr
      assert PutLocale.get_locale_source(conn) == :accept_language
    end

    test "is :route for a locale the route set" do
      {:ok, route_locale} = Localize.validate_locale("fr")

      conn =
        :get
        |> conn("/")
        |> put_private(:localize_locale, route_locale)
        |> PutLocale.call(PutLocale.init([]))

      assert PutLocale.get_locale_source(conn) == :route
    end

    test "is the tuple for a source that is a function" do
      assert PutLocale.get_locale_source(resolve("/", [{MyModule, :get_locale}])) ==
               {MyModule, :get_locale}

      assert PutLocale.get_locale_source(resolve("/", [{MyModule, :get_locale, [:fred]}])) ==
               {MyModule, :get_locale, [:fred]}
    end

    test "is :default when no source has a locale" do
      conn = resolve("/", [:query, :accept_language])

      assert PutLocale.get_locale(conn) == @default_locale
      assert PutLocale.get_locale_source(conn) == :default
    end

    test "is nil when nothing is found and there is no default" do
      conn =
        :get
        |> conn("/")
        |> PutLocale.call(PutLocale.init(from: [:query], default: :none))

      assert PutLocale.get_locale(conn) == nil
      assert PutLocale.get_locale_source(conn) == nil
    end

    test "is nil for a conn the plug has not seen, and for anything that is not a conn" do
      for value <- [conn(:get, "/"), nil, %{}, "conn", :conn] do
        assert PutLocale.get_locale_source(value) == nil
      end
    end
  end

  describe "call/2 - a valid locale the application does not support" do
    # `tlh` is a valid tag CLDR has no data for, which Localize resolves to
    # the root locale `und`. `pt`, `ru` and `es-MX` are locales too distant
    # from every supported one, which Localize resolves to the first
    # supported locale. Each source is followed by accept-language.
    @sources %{
      query: &__MODULE__.in_query/1,
      path: &__MODULE__.in_path/1,
      body: &__MODULE__.in_body/1,
      cookie: &__MODULE__.in_cookie/1,
      session: &__MODULE__.in_session/1,
      route: &__MODULE__.in_route/1
    }

    def in_query(value), do: conn(:get, "/?locale=" <> value)
    def in_path(value), do: %{conn(:get, "/") | path_params: %{"locale" => value}}
    def in_body(value), do: %{conn(:get, "/") | body_params: %{"locale" => value}}
    def in_session(value), do: init_test_session(conn(:get, "/"), %{"localize_locale" => value})
    def in_route(value), do: put_private(conn(:get, "/"), :localize_locale, value)

    def in_cookie(value) do
      :get
      |> conn("/")
      |> put_req_cookie("locale", value)
      |> fetch_cookies()
    end

    defp resolved(conn, from) do
      conn
      |> put_req_header("accept-language", "fr")
      |> PutLocale.call(PutLocale.init(from: from))
    end

    test "is a miss in every source that takes an identifier, so the next source decides" do
      for {source, build} <- @sources,
          value <- ["tlh", "TLH", "tlh-u-nu-latn", "pt", "ru", "es-MX"] do
        conn = resolved(build.(value), [source, :accept_language])

        assert {source, value, PutLocale.get_locale(conn).cldr_locale_id} == {source, value, :fr}
        assert PutLocale.get_locale_source(conn) == :accept_language
      end
    end

    test "falls to the default locale when no later source has one" do
      conn = PutLocale.call(conn(:get, "/?locale=tlh"), PutLocale.init(from: [:query]))

      assert PutLocale.get_locale(conn) == @default_locale
      assert PutLocale.get_locale_source(conn) == :default
    end

    test "leaves the locale unset when there is no default either" do
      conn =
        PutLocale.call(conn(:get, "/?locale=tlh"), PutLocale.init(from: [:query], default: :none))

      assert PutLocale.get_locale(conn) == nil
      assert PutLocale.get_locale_source(conn) == nil
    end

    test "keeps the root locale when it is what was asked for" do
      for value <- ["und", "UND", "root", "und-u-nu-latn", "und_u_nu_latn"] do
        conn = resolved(conn(:get, "/?locale=" <> value), [:query, :accept_language])

        assert {value, PutLocale.get_locale(conn).cldr_locale_id} == {value, :und}
        assert PutLocale.get_locale_source(conn) == :query
      end

      conn =
        resolved(put_private(conn(:get, "/"), :localize_locale, :und), [:route, :accept_language])

      assert PutLocale.get_locale(conn).cldr_locale_id == :und
    end

    test "treats a tag that was parsed and not validated the same way" do
      {:ok, unmatched} = Localize.LanguageTag.parse("tlh")

      conn =
        resolved(put_private(conn(:get, "/"), :localize_locale, unmatched), [
          :route,
          :accept_language
        ])

      assert PutLocale.get_locale(conn).cldr_locale_id == :fr
      assert PutLocale.get_locale_source(conn) == :accept_language

      {:ok, root} = Localize.LanguageTag.parse("und")

      conn =
        resolved(put_private(conn(:get, "/"), :localize_locale, root), [:route, :accept_language])

      assert PutLocale.get_locale(conn).cldr_locale_id == :und
      assert PutLocale.get_locale_source(conn) == :route
    end

    test "is not stored as a choice by PutSession" do
      conn =
        :get
        |> conn("/?locale=tlh")
        |> init_test_session(%{})
        |> put_req_header("accept-language", "fr")
        |> PutLocale.call(PutLocale.init([]))
        |> Localize.Plug.PutSession.call(Localize.Plug.PutSession.init(from: [:query]))

      assert PutLocale.get_locale(conn).cldr_locale_id == :fr
      assert get_session(conn, "localize_locale") == nil
      refute Localize.Plug.PutSession.stored?(conn)
    end

    test "still takes a locale that matches a supported one" do
      for {value, expected} <- [
            {"fr-CA", :fr},
            {"zh-TW", :"zh-Hant"},
            {"en-AU", :en},
            {"de", :de}
          ] do
        conn = resolved(conn(:get, "/?locale=" <> value), [:query, :accept_language])

        assert {value, PutLocale.get_locale(conn).cldr_locale_id} == {value, expected}
        assert PutLocale.get_locale_source(conn) == :query
      end
    end

    test "falls to the default locale for a distant locale with no later source" do
      conn = PutLocale.call(conn(:get, "/?locale=pt"), PutLocale.init(from: [:query]))

      assert PutLocale.get_locale(conn) == @default_locale
      assert PutLocale.get_locale_source(conn) == :default
    end
  end

  describe "call/2 - a list of supported locales" do
    @identifier_sources %{
      query: &__MODULE__.in_query/1,
      path: &__MODULE__.in_path/1,
      body: &__MODULE__.in_body/1,
      cookie: &__MODULE__.in_cookie/1,
      session: &__MODULE__.in_session/1,
      route: &__MODULE__.in_route/1
    }

    def site_locales(%Plug.Conn{host: "example.de"}, _options) do
      ["de", "en"]
    end

    def site_locales(%Plug.Conn{}, _options) do
      ["en", "fr"]
    end

    def not_a_list(%Plug.Conn{}, _options) do
      {:ok, ["en"]}
    end

    # A `:from` source that hands back the list it was given, as the
    # locale `ja` when the list was resolved and `th` when it was not.
    def from_supported(%Plug.Conn{}, options) do
      if is_list(options[:supported]) do
        Localize.validate_locale("ja")
      else
        Localize.validate_locale("th")
      end
    end

    defp call_with(conn, options) do
      PutLocale.call(conn, PutLocale.init(options))
    end

    test "takes an identifier that matches an entry, as that entry, from every source" do
      {:ok, french} = Localize.validate_locale("fr")

      for {source, build} <- @identifier_sources, value <- ["fr", "fr-CA", "FR_ch"] do
        conn = call_with(build.(value), from: [source], supported: ["en", "fr"])

        assert {source, value, PutLocale.get_locale(conn)} == {source, value, french}

        assert PutLocale.get_locale_source(conn) == source
      end
    end

    test "passes over an identifier that matches no entry, so the next source decides" do
      for {source, build} <- @identifier_sources, value <- ["de", "it-CH", "und", "tlh"] do
        conn =
          value
          |> build.()
          |> put_req_header("accept-language", "fr")
          |> call_with(from: [source, :accept_language], supported: ["en", "fr"])

        assert {source, value, PutLocale.get_locale(conn).cldr_locale_id} ==
                 {source, value, :fr}

        assert PutLocale.get_locale_source(conn) == :accept_language
      end
    end

    test "keeps a validated tag from the route as it stands" do
      {:ok, german} = Localize.validate_locale("de")
      conn = call_with(in_route(german), from: [:route], supported: ["en", "fr"])

      assert PutLocale.get_locale(conn) == german
    end

    test "matches the accept-language header against the list" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "de-CH, it;q=0.9, en;q=0.5")
        |> call_with(from: [:accept_language], supported: ["en", "fr"])

      assert PutLocale.get_locale(conn).cldr_locale_id == :en
    end

    test "takes the host's locale only when it matches an entry" do
      conn = call_with(conn(:get, "http://example.fr/"), from: [:host], supported: ["en", "fr"])
      assert PutLocale.get_locale(conn).cldr_locale_id == :fr
      assert PutLocale.get_locale_source(conn) == :host

      conn = call_with(conn(:get, "http://example.de/"), from: [:host], supported: ["en", "fr"])
      assert PutLocale.get_locale(conn) == @default_locale
      assert PutLocale.get_locale_source(conn) == :default
    end

    test "calls a function with the request for the list" do
      supported = {__MODULE__, :site_locales}

      for {host, expected} <- [{"example.de", :de}, {"example.fr", :fr}] do
        conn =
          :get
          |> conn("http://#{host}/?locale=de")
          |> put_req_header("accept-language", "fr")
          |> call_with(from: [:query, :accept_language], supported: supported)

        assert {host, PutLocale.get_locale(conn).cldr_locale_id} == {host, expected}
      end
    end

    test "gives a {Module, function} source the resolved list" do
      conn =
        call_with(conn(:get, "/"),
          from: [{__MODULE__, :from_supported}],
          supported: {__MODULE__, :site_locales}
        )

      assert PutLocale.get_locale(conn).cldr_locale_id == :ja
    end

    test "takes no locale from the request when the function returns something other than a list" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          conn =
            :get
            |> conn("/?locale=en")
            |> put_req_header("accept-language", "en")
            |> call_with(from: [:query, :accept_language], supported: {__MODULE__, :not_a_list})

          assert PutLocale.get_locale_source(conn) == :default
        end)

      assert log =~ "for the :supported option"
    end

    @tag :capture_log
    test "takes no locale from the request with an empty list" do
      conn =
        :get
        |> conn("/?locale=en")
        |> put_req_header("accept-language", "en")
        |> call_with(from: [:query, :accept_language], supported: [])

      assert PutLocale.get_locale_source(conn) == :default
    end

    test "init/1 raises for a value that is not a list or a function" do
      for supported <- ["en", :en, %{}, {"Module", :function}, [1], [%{}]] do
        assert_raise ArgumentError, ~r/Invalid :supported/, fn ->
          PutLocale.init(supported: supported)
        end
      end
    end
  end

  describe "call/2 - set locale from the path prefix" do
    def prefix_locales(%Plug.Conn{host: "example.de"}, _options) do
      ["de", "en"]
    end

    def prefix_locales(%Plug.Conn{}, _options) do
      [42, nil, "en", "fr"]
    end

    defp prefixed(path, options, headers \\ []) do
      conn =
        Enum.reduce(headers, conn(:get, path), fn {name, value}, conn ->
          put_req_header(conn, name, value)
        end)

      PutLocale.call(conn, PutLocale.init(options))
    end

    test "takes a first segment that names a configured locale, in any case and either separator" do
      for {path, locale_id} <- [
            {"/fr/about", :fr},
            {"/FR", :fr},
            {"/zh-hant/blog/post", :"zh-Hant"},
            {"/ZH_HANT", :"zh-Hant"},
            {"/it-ch/", :"it-CH"}
          ] do
        conn = prefixed(path, from: [:path_prefix])

        assert {path, PutLocale.get_locale(conn).cldr_locale_id} == {path, locale_id}
        assert PutLocale.get_locale_source(conn) == :path_prefix
      end
    end

    test "takes only a segment that names a supported locale, never the closest one" do
      for path <- ["/fr-ca/about", "/de/about", "/fra/about", "/en-us"] do
        conn =
          prefixed(path, [from: [:path_prefix, :accept_language], supported: ["en", "fr"]], [
            {"accept-language", "fr"}
          ])

        assert {path, PutLocale.get_locale_source(conn)} == {path, :accept_language}
        assert PutLocale.get_locale(conn).cldr_locale_id == :fr
      end
    end

    test "matches the supported list a function returns for the request" do
      german =
        prefixed("http://example.de/de/blog",
          from: [:path_prefix],
          supported: {__MODULE__, :prefix_locales}
        )

      other =
        prefixed("http://example.com/de/blog",
          from: [:path_prefix],
          supported: {__MODULE__, :prefix_locales}
        )

      french =
        prefixed("http://example.com/fr/blog",
          from: [:path_prefix],
          supported: {__MODULE__, :prefix_locales}
        )

      assert PutLocale.get_locale(german).cldr_locale_id == :de
      assert PutLocale.get_locale_source(other) == :default
      assert PutLocale.get_locale(french).cldr_locale_id == :fr
    end

    test "is a miss for a path with no locale segment, so the default decides" do
      for path <- ["/", "/about", "/blog/fr", "/%E2%9C%93", "/" <> String.duplicate("x", 5000)] do
        conn = prefixed(path, from: [:path_prefix], supported: ["en", "fr"])

        assert {path, PutLocale.get_locale_source(conn)} == {path, :default}
        assert PutLocale.get_locale(conn) == @default_locale
      end
    end

    test "takes the root locale only when the list holds it" do
      assert PutLocale.get_locale_source(
               prefixed("/und/x", from: [:path_prefix], supported: ["en"])
             ) ==
               :default

      assert PutLocale.get_locale(prefixed("/und/x", from: [:path_prefix])).cldr_locale_id == :und
    end

    test "adds no vary header, as the address names the language" do
      conn = prefixed("/fr/about", from: [:path_prefix])

      assert get_resp_header(conn, "vary") == []
    end

    test "is a source Localize.Plug.PutSession may store" do
      assert Localize.Plug.PutSession.init(from: [:path_prefix])
    end
  end

  describe "call/2 - a host whose locale the application does not support" do
    test "is a miss, so the next source decides" do
      # Brazil's language, Portuguese, is not a configured locale.
      conn =
        :get
        |> conn("http://example.br/")
        |> put_req_header("accept-language", "fr")
        |> PutLocale.call(PutLocale.init(from: [:host, :accept_language]))

      assert PutLocale.get_locale(conn).cldr_locale_id == :fr
      assert PutLocale.get_locale_source(conn) == :accept_language
    end
  end
end
