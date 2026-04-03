defmodule Localize.Plug.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Localize.Plug.PutLocale

  describe "Plug.Router integration with path params" do
    test "sets locale from :locale path parameter" do
      conn = conn(:get, "/thing/en")
      conn = SimplePlugRouter.call(conn, SimplePlugRouter.init([]))

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :en
      assert locale.language == :en
    end

    test "sets locale from path parameter with nested route" do
      conn = conn(:get, "/thing/de/other")
      conn = SimplePlugRouter.call(conn, SimplePlugRouter.init([]))

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :de
      assert locale.language == :de
    end

    test "sets locale from path parameter with different locale" do
      conn = conn(:get, "/thing/fr")
      conn = SimplePlugRouter.call(conn, SimplePlugRouter.init([]))

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :fr
      assert locale.language == :fr
    end
  end

  describe "Plug.Router integration with query params" do
    test "path param takes priority when it appears first in :from" do
      conn =
        :get
        |> conn("/hello/en?locale=de")
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))

      conn = MyPlugRouter.call(conn, MyPlugRouter.init([]))

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      # MyPlugRouter has from: [:path, :query, :route], so path wins
      assert locale.cldr_locale_id == :en
    end
  end

  describe "Plug.Router integration with route private" do
    test "sets locale from route private localize_locale" do
      conn =
        :get
        |> conn("/hello")
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))

      conn = MyPlugRouter.call(conn, MyPlugRouter.init([]))

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :fr
      assert locale.language == :fr
    end
  end

  describe "Plug.Router integration with session" do
    test "stores locale in session" do
      conn =
        :get
        |> conn("/hello/de")
        |> put_in([Access.key(:secret_key_base)], String.duplicate("X", 64))

      conn = MyPlugRouter.call(conn, MyPlugRouter.init([]))

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.cldr_locale_id == :de

      session_value = get_session(conn, PutLocale.session_key())
      assert session_value != nil
    end
  end
end
