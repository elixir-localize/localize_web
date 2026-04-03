defmodule Localize.Plug.PutSessionTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Localize.Plug.PutLocale
  alias Localize.Plug.PutSession

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
      assert options == %{as: :string}
    end

    test "accepts :string format" do
      options = PutSession.init(as: :string)
      assert options == %{as: :string}
    end

    test "accepts :language_tag format" do
      options = PutSession.init(as: :language_tag)
      assert options == %{as: :language_tag}
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
end
