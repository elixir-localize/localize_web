defmodule Localize.Plug.PutSessionTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Localize.Plug.PutLocale
  alias Localize.Plug.PutSession

  doctest Localize.Plug.PutSession

  @session_options Plug.Session.init(store: :cookie, key: "_key", signing_salt: "X")

  defp session_conn(locale_string) do
    options = PutLocale.init(from: [:query], apps: [:localize])

    :get
    |> conn("/?locale=#{locale_string}")
    |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))
    |> Plug.Session.call(@session_options)
    |> fetch_session()
    |> PutLocale.call(options)
  end

  describe "init/1" do
    test "default options" do
      options = PutSession.init([])
      assert options == %{as: :string, from: :all}
    end

    test "accepts :string format" do
      options = PutSession.init(as: :string)
      assert options == %{as: :string, from: :all}
    end

    test "accepts :language_tag format" do
      options = PutSession.init(as: :language_tag)
      assert options == %{as: :language_tag, from: :all}
    end

    test "raises on invalid :as option" do
      assert_raise ArgumentError, ~r/Invalid option for `:as`/, fn ->
        PutSession.init(as: :invalid)
      end
    end

    test "raises on unknown options" do
      assert_raise ArgumentError, ~r/Invalid options/, fn ->
        PutSession.init(as: :string, unknown: true)
      end
    end
  end

  describe "call/2 - string format" do
    test "stores locale as string in session" do
      session_options = PutSession.init(as: :string)

      conn =
        "fr"
        |> session_conn()
        |> PutSession.call(session_options)

      session_value = get_session(conn, "localize_locale")
      assert is_binary(session_value)
      assert session_value =~ "fr"
    end

    test "stores locale with territory as string" do
      session_options = PutSession.init(as: :string)

      conn =
        "en-GB"
        |> session_conn()
        |> PutSession.call(session_options)

      session_value = get_session(conn, "localize_locale")
      assert is_binary(session_value)
    end
  end

  describe "call/2 - language_tag format" do
    test "stores locale as LanguageTag struct in session" do
      session_options = PutSession.init(as: :language_tag)

      conn =
        "fr"
        |> session_conn()
        |> PutSession.call(session_options)

      session_value = get_session(conn, "localize_locale")
      assert %Localize.LanguageTag{} = session_value
      assert session_value.cldr_locale_id == :fr
      assert session_value.language == :fr
    end
  end

  describe "call/2 - no locale set" do
    test "does not modify session when no locale is set" do
      session_options = PutSession.init(as: :string)

      conn =
        :get
        |> conn("/")
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))
        |> Plug.Session.call(@session_options)
        |> fetch_session()
        |> PutSession.call(session_options)

      session_value = get_session(conn, "localize_locale")
      assert session_value == nil
    end
  end

  describe "call/2 - avoids needless session writes" do
    test "does not rewrite the session when the stored locale is unchanged" do
      session_options = PutSession.init(as: :string)
      put_locale_options = PutLocale.init(from: [:query], apps: [:localize])

      # First request: the locale is written to the session, so a session
      # cookie is set on the response.
      conn1 =
        "fr"
        |> session_conn()
        |> PutSession.call(session_options)
        |> send_resp(200, "")

      assert conn1.resp_cookies != %{}
      assert get_session(conn1, "localize_locale") =~ "fr"

      # Second request carrying that cookie and resolving to the same locale.
      conn2 =
        :get
        |> conn("/?locale=fr")
        |> recycle_cookies(conn1)
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))
        |> Plug.Session.call(@session_options)
        |> fetch_session()
        |> PutLocale.call(put_locale_options)
        |> PutSession.call(session_options)
        |> send_resp(200, "")

      # The session already holds this locale, so no Set-Cookie is emitted.
      assert conn2.resp_cookies == %{}
      assert get_session(conn2, "localize_locale") =~ "fr"
    end
  end

  describe "session key" do
    test "uses the standard session key" do
      assert PutLocale.session_key() == "localize_locale"
    end
  end

  describe "round-trip: session write then read" do
    test "locale stored as string can be read back by PutLocale" do
      put_session_options = PutSession.init(as: :string)
      put_locale_options = PutLocale.init(from: [:session], apps: [:localize])

      # First request: set locale from query and store in session
      conn1 =
        "de"
        |> session_conn()
        |> PutSession.call(put_session_options)

      session_value = get_session(conn1, "localize_locale")
      assert is_binary(session_value)

      # Second request: read locale from session
      conn2 =
        :get
        |> conn("/")
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))
        |> Plug.Session.call(@session_options)
        |> fetch_session()
        |> put_session("localize_locale", session_value)
        |> PutLocale.call(put_locale_options)

      locale = conn2.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :de
    end

    test "locale stored as language_tag can be read back by PutLocale" do
      put_session_options = PutSession.init(as: :language_tag)
      put_locale_options = PutLocale.init(from: [:session], apps: [:localize])

      # First request: set locale from query and store in session
      conn1 =
        "fr"
        |> session_conn()
        |> PutSession.call(put_session_options)

      session_value = get_session(conn1, "localize_locale")
      assert %Localize.LanguageTag{} = session_value

      # Second request: read locale from session
      conn2 =
        :get
        |> conn("/")
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))
        |> Plug.Session.call(@session_options)
        |> fetch_session()
        |> put_session("localize_locale", session_value)
        |> PutLocale.call(put_locale_options)

      locale = conn2.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :fr
    end
  end

  describe "init/1 - the :from option" do
    test "accepts :all, source names, :default and function sources" do
      assert PutSession.init(from: :all).from == :all

      from = [:route, :path, :query, :body, :cookie, :session, :host, :accept_language, :default]
      assert PutSession.init(from: from).from == from

      functions = [{MyModule, :get_locale}, {MyModule, :get_locale, [:fred]}]
      assert PutSession.init(from: functions).from == functions
    end

    test "raises on a :from that is not :all or a list of sources" do
      for invalid <- [nil, [], :query, "query", %{}, 1] do
        assert_raise ArgumentError, ~r/Invalid option for `:from`/, fn ->
          PutSession.init(from: invalid)
        end
      end
    end

    test "raises on an entry that is not a source, and names it" do
      for invalid <- [:nope, "query", {MyModule}, {MyModule, "get_locale"}, {MyModule, :f, :args}] do
        assert_raise ArgumentError, ~r/Invalid option for `:from`.*Found \[/s, fn ->
          PutSession.init(from: [:query, invalid])
        end
      end
    end
  end

  describe "call/2 - the :from option" do
    # A request with a session, resolved by `PutLocale` with its default
    # sources, and then through `PutSession` with the options given.
    defp visit(path, session_options, setup \\ & &1) do
      :get
      |> conn(path)
      |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))
      |> Plug.Session.call(@session_options)
      |> fetch_session()
      |> fetch_query_params()
      |> setup.()
      |> PutLocale.call(PutLocale.init([]))
      |> PutSession.call(PutSession.init(session_options))
      |> send_resp(200, "")
    end

    @chosen [from: [:route, :path, :query, :body]]

    test "stores a locale from a listed source" do
      conn = visit("/?locale=fr", @chosen)

      assert PutLocale.get_locale_source(conn) == :query
      assert get_session(conn, "localize_locale") == "fr"
      assert conn.resp_cookies != %{}
    end

    test "does not store a locale inferred from accept-language, and sets no cookie" do
      conn = visit("/", @chosen, &put_req_header(&1, "accept-language", "fr"))

      assert PutLocale.get_locale(conn).cldr_locale_id == :fr
      assert PutLocale.get_locale_source(conn) == :accept_language
      assert get_session(conn, "localize_locale") == nil
      assert conn.resp_cookies == %{}
    end

    test "does not store the default locale, unless :default is listed" do
      conn = visit("/", @chosen)

      assert PutLocale.get_locale_source(conn) == :default
      assert get_session(conn, "localize_locale") == nil
      assert conn.resp_cookies == %{}

      conn = visit("/", from: [:query, :default])

      assert is_binary(get_session(conn, "localize_locale"))
    end

    test "leaves a stored locale alone, and it goes on deciding" do
      conn =
        visit("/", @chosen, fn conn ->
          conn
          |> put_session("localize_locale", "de")
          |> put_req_header("accept-language", "fr")
        end)

      assert PutLocale.get_locale(conn).cldr_locale_id == :de
      assert PutLocale.get_locale_source(conn) == :session
      assert get_session(conn, "localize_locale") == "de"
    end

    test "replaces a stored locale when the visitor chooses another" do
      conn = visit("/?locale=fr", @chosen, &put_session(&1, "localize_locale", "de"))

      assert get_session(conn, "localize_locale") == "fr"
    end

    test "stores a locale from a function source that is listed, and not one that is not" do
      function = {MyModule, :get_locale}

      resolved = fn session_options ->
        :get
        |> conn("/")
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))
        |> Plug.Session.call(@session_options)
        |> fetch_session()
        |> PutLocale.call(PutLocale.init(from: [function]))
        |> PutSession.call(PutSession.init(session_options))
      end

      assert get_session(resolved.(from: [function]), "localize_locale") == "fr"
      assert get_session(resolved.(from: [:query]), "localize_locale") == nil
    end

    test "with the default :all, stores a locale from any source as before" do
      conn = visit("/", [], &put_req_header(&1, "accept-language", "fr"))

      assert get_session(conn, "localize_locale") == "fr"
      assert conn.resp_cookies != %{}
    end
  end

  describe "stored?/1" do
    test "is true when the plug writes the locale, and false on the next request" do
      first = visit("/?locale=fr", [])

      assert PutSession.stored?(first)
      assert first.resp_cookies != %{}

      second =
        :get
        |> conn("/?locale=fr")
        |> recycle_cookies(first)
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))
        |> Plug.Session.call(@session_options)
        |> fetch_session()
        |> fetch_query_params()
        |> PutLocale.call(PutLocale.init([]))
        |> PutSession.call(PutSession.init([]))
        |> send_resp(200, "")

      refute PutSession.stored?(second)
      assert second.resp_cookies == %{}
    end

    test "is true when a stored locale is replaced" do
      conn = visit("/?locale=fr", [], &put_session(&1, "localize_locale", "de"))

      assert PutSession.stored?(conn)
    end

    test "is false when :from leaves the deciding source out" do
      conn = visit("/", @chosen, &put_req_header(&1, "accept-language", "fr"))

      refute PutSession.stored?(conn)
    end

    test "is false when the session already holds the locale" do
      conn = visit("/", [], &put_session(&1, "localize_locale", "de"))

      assert PutLocale.get_locale_source(conn) == :session
      refute PutSession.stored?(conn)
    end

    test "is false before the plug runs, and for anything that is not a conn" do
      for value <- [conn(:get, "/"), nil, %{}, "conn", :conn] do
        refute PutSession.stored?(value)
      end
    end
  end
end
