defmodule Localize.Plug.AcceptLanguageTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Localize.Plug.AcceptLanguage

  doctest Localize.Plug.AcceptLanguage

  describe "init/1" do
    test "default options" do
      options = AcceptLanguage.init([])
      assert options == %{log_level: :warning, supported: nil}
    end

    test "accepts custom log level" do
      options = AcceptLanguage.init(no_match_log_level: :error)
      assert options == %{log_level: :error, supported: nil}
    end

    test "accepts nil log level to disable logging" do
      options = AcceptLanguage.init(no_match_log_level: nil)
      assert options == %{log_level: nil, supported: nil}
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

    @tag :capture_log
    test "sets nil for unrecognized accept-language content" do
      options = AcceptLanguage.init([])

      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "!!!")
        |> AcceptLanguage.call(options)

      assert conn.private[:localize_locale] == nil
    end

    # `capture_log/1` gathers what every process logs while it runs, and this
    # module runs alongside others, so each test sends a header of its own and
    # looks for that header in the log rather than for the log as a whole.
    test "logs warning when no matching locale found" do
      options = AcceptLanguage.init([])
      header = unmatched_header()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :get
          |> conn("/")
          |> put_req_header("accept-language", header)
          |> AcceptLanguage.call(options)
        end)

      assert log =~ "Localize.Plug.AcceptLanguage"
      assert log =~ header
    end

    test "does not log when log level is nil" do
      options = AcceptLanguage.init(no_match_log_level: nil)
      header = unmatched_header()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :get
          |> conn("/")
          |> put_req_header("accept-language", header)
          |> AcceptLanguage.call(options)
        end)

      refute log =~ header
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

  describe "the :supported option" do
    def supported_for_host(%Plug.Conn{host: "example.de"}, _options) do
      ["de", "en"]
    end

    def supported_for_host(%Plug.Conn{}, _options) do
      ["en", "fr"]
    end

    def supported_with_args(%Plug.Conn{}, _options, locales) do
      locales
    end

    def not_a_list(%Plug.Conn{}, _options) do
      :none
    end

    defp matched(conn, header, options) do
      conn
      |> put_req_header("accept-language", header)
      |> AcceptLanguage.call(AcceptLanguage.init(options))
      |> AcceptLanguage.get_locale()
    end

    test "init/1 keeps a list and completes a {Module, function} tuple" do
      assert AcceptLanguage.init(supported: ["en", :fr]).supported == ["en", :fr]

      assert AcceptLanguage.init(supported: {__MODULE__, :supported_for_host}).supported ==
               {__MODULE__, :supported_for_host, []}
    end

    test "init/1 raises for a value that is not a list or a function" do
      for supported <- ["en", :en, %{}, {"Module", :function}, [1], [%{}]] do
        assert_raise ArgumentError, ~r/Invalid :supported/, fn ->
          AcceptLanguage.init(supported: supported)
        end
      end
    end

    test "matches the header against a list" do
      locale = matched(conn(:get, "/"), "de-CH,fr;q=0.8", supported: ["en", "fr"])

      assert locale.cldr_locale_id == :fr
    end

    test "matches the header against the list a function returns for the request" do
      supported = {__MODULE__, :supported_for_host}

      assert matched(conn(:get, "http://example.de/"), "de-CH,fr;q=0.8", supported: supported).cldr_locale_id ==
               :de

      assert matched(conn(:get, "http://example.fr/"), "de-CH,fr;q=0.8", supported: supported).cldr_locale_id ==
               :fr
    end

    test "passes the extra arguments of a {Module, function, args} tuple" do
      supported = {__MODULE__, :supported_with_args, [["ja"]]}

      assert matched(conn(:get, "/"), "ja-JP,en;q=0.5", supported: supported).cldr_locale_id ==
               :ja
    end

    @tag :capture_log
    test "sets no locale when no tag matches the list" do
      assert matched(conn(:get, "/"), "de", supported: ["en", "fr"]) == nil
    end

    test "sets no locale, and logs, when the function returns something other than a list" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert matched(conn(:get, "/"), "en", supported: {__MODULE__, :not_a_list}) == nil
        end)

      assert log =~ "for the :supported option"
    end

    test "best_match/2 takes the list in its options map" do
      locale = AcceptLanguage.best_match("de-CH,fr;q=0.8", %{log_level: nil, supported: ["fr"]})

      assert locale.cldr_locale_id == :fr
    end
  end

  # An Accept-Language value that matches no locale and appears in no other
  # test's log.
  defp unmatched_header, do: "!!!-#{System.unique_integer([:positive])}"
end
