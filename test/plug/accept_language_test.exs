defmodule Localize.Plug.AcceptLanguageTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Localize.Plug.AcceptLanguage

  describe "init/1" do
    test "default options" do
      options = AcceptLanguage.init([])
      assert options == %{log_level: :warning}
    end

    test "accepts custom log level" do
      options = AcceptLanguage.init(no_match_log_level: :error)
      assert options == %{log_level: :error}
    end

    test "accepts nil log level to disable logging" do
      options = AcceptLanguage.init(no_match_log_level: nil)
      assert options == %{log_level: nil}
    end
  end

  describe "call/2" do
    test "sets locale from accept-language header" do
      options = AcceptLanguage.init([])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "en")
        |> AcceptLanguage.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.language == :en
      assert locale.cldr_locale_id == :en
    end

    test "sets locale from complex accept-language header" do
      options = AcceptLanguage.init([])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "fr-CH, fr;q=0.9, en;q=0.8, de;q=0.7, *;q=0.5")
        |> AcceptLanguage.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.language == :fr
    end

    test "sets nil when no accept-language header is present" do
      options = AcceptLanguage.init([])

      conn =
        :get
        |> conn("/")
        |> AcceptLanguage.call(options)

      assert conn.private[:localize_locale] == nil
    end

    test "sets nil for unrecognized accept-language content" do
      options = AcceptLanguage.init([])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "!!!")
        |> AcceptLanguage.call(options)

      assert conn.private[:localize_locale] == nil
    end

    test "logs warning when no matching locale found" do
      options = AcceptLanguage.init([])

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :get
          |> conn("/")
          |> put_req_header("accept-language", "!!!")
          |> AcceptLanguage.call(options)
        end)

      assert log =~ "!!!"
    end

    test "does not log when log level is nil" do
      options = AcceptLanguage.init(no_match_log_level: nil)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :get
          |> conn("/")
          |> put_req_header("accept-language", "!!!")
          |> AcceptLanguage.call(options)
        end)

      assert log == ""
    end

    test "selects highest quality matching locale" do
      options = AcceptLanguage.init([])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "en-US,en;q=0.9,de;q=0.8")
        |> AcceptLanguage.call(options)

      locale = conn.private[:localize_locale]
      assert %Localize.LanguageTag{} = locale
      assert locale.language == :en
    end
  end

  describe "get_locale/1" do
    test "returns locale from conn" do
      options = AcceptLanguage.init([])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "de")
        |> AcceptLanguage.call(options)

      locale = AcceptLanguage.get_locale(conn)
      assert %Localize.LanguageTag{} = locale
      assert locale.language == :de
    end

    test "returns nil when no locale set" do
      options = AcceptLanguage.init([])

      conn =
        :get
        |> conn("/")
        |> AcceptLanguage.call(options)

      assert AcceptLanguage.get_locale(conn) == nil
    end
  end
end
