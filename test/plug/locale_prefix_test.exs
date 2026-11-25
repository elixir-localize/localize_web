defmodule Localize.Plug.LocalePrefixTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureLog

  alias Localize.Plug.{LocalePrefix, PutLocale}

  doctest Localize.Plug.LocalePrefix

  @put_locale [
    from: [:path_prefix, :session, :accept_language],
    supported: ["en", "fr", "de"],
    default: "en"
  ]

  defp request(path, prefix_options, setup \\ []) do
    method = Keyword.get(setup, :method, :get)
    put_locale = Keyword.merge(@put_locale, Keyword.get(setup, :put_locale, []))

    conn =
      method
      |> conn(path)
      |> init_test_session(Keyword.get(setup, :session, %{}))
      |> add_headers(Keyword.get(setup, :headers, []))
      |> Map.merge(Keyword.get(setup, :conn, %{}))
      |> PutLocale.call(PutLocale.init(put_locale))

    LocalePrefix.call(conn, LocalePrefix.init(prefix_options))
  end

  defp add_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
  end

  defp redirect(conn) do
    {conn.status, get_resp_header(conn, "location"), conn.halted}
  end

  defp served(conn) do
    {conn.halted, PutLocale.get_locale(conn).cldr_locale_id, PutLocale.get_locale_source(conn)}
  end

  def url_mode(%Localize.Routes.Request{host: "all.example"}) do
    :prefix_all
  end

  def url_mode(_conn) do
    :prefix_others
  end

  def site_locales(%Localize.Routes.Request{host: "de.example"}, extra) do
    ["de" | extra]
  end

  def site_locales(_conn, extra) do
    ["en", "fr" | extra]
  end

  def published?(
        %Localize.Routes.Request{} = _request,
        rest,
        locale,
        published \\ %{"/about" => [:en, :fr]}
      ) do
    locale.cldr_locale_id in Map.get(published, rest, [])
  end

  def bad_mode(_conn) do
    :prefix_some
  end

  describe "under :prefix_others" do
    test "redirects the default locale's prefix with a 301, keeping the query string" do
      assert redirect(request("/en/about", [])) == {301, ["/about"], true}

      assert redirect(request("/en/about?page=2&q=a%20b", [])) ==
               {301, ["/about?page=2&q=a%20b"], true}

      assert redirect(request("/en", [])) == {301, ["/"], true}
      assert redirect(request("/EN/about/", [])) == {301, ["/about"], true}
    end

    test "serves a prefixed address in the locale it names" do
      assert served(request("/fr/about", [])) == {false, :fr, :path_prefix}

      assert served(request("/de", [], session: %{"localize_locale" => "fr"})) ==
               {false, :de, :path_prefix}
    end

    test "serves an address with no prefix in the default locale, whatever the visitor's" do
      for setup <- [
            [],
            [session: %{"localize_locale" => "fr"}],
            [headers: [{"accept-language", "de"}]]
          ] do
        assert served(request("/about", [], setup)) == {false, :en, :default}, inspect(setup)
      end
    end

    test "sets the replaced locale for Localize, Gettext and content-language" do
      conn =
        request("/about", [],
          session: %{"localize_locale" => "fr"},
          put_locale: [gettext: MyApp.Gettext, content_language: true]
        )

      assert Localize.get_locale().cldr_locale_id == :en
      assert Gettext.get_locale(MyApp.Gettext) == "en"
      assert get_resp_header(conn, "content-language") == ["en"]
    end
  end

  describe "under :prefix_all" do
    test "redirects an address with no prefix to the visitor's locale with a 302" do
      assert redirect(
               request("/about", [mode: :prefix_all], session: %{"localize_locale" => "fr"})
             ) ==
               {302, ["/fr/about"], true}

      assert redirect(
               request("/about?page=2", [mode: :prefix_all], headers: [{"accept-language", "de"}])
             ) == {302, ["/de/about?page=2"], true}

      assert redirect(request("/", [mode: :prefix_all], headers: [{"accept-language", "fr"}])) ==
               {302, ["/fr"], true}
    end

    test "redirects a visitor with no locale to the default locale" do
      assert redirect(request("/about", mode: :prefix_all)) == {302, ["/en/about"], true}
    end

    test "carries the vary of the sources read on a 302" do
      conn = request("/about", [mode: :prefix_all], headers: [{"accept-language", "fr"}])

      assert conn.status == 302
      assert get_resp_header(conn, "vary") == ["cookie, accept-language"]
    end

    test "serves a prefixed address in the locale it names, the default's included" do
      assert served(request("/en/about", mode: :prefix_all)) == {false, :en, :path_prefix}
      assert served(request("/fr/about", mode: :prefix_all)) == {false, :fr, :path_prefix}
    end

    test "redirects to the default locale when :exists? says the page is not in the visitor's" do
      for exists <- [
            {__MODULE__, :published?},
            {__MODULE__, :published?, [%{"/about" => [:en, :fr]}]}
          ] do
        options = [mode: :prefix_all, exists?: exists]
        french = [headers: [{"accept-language", "fr"}]]
        german = [headers: [{"accept-language", "de"}]]

        assert redirect(request("/about", options, french)) == {302, ["/fr/about"], true}
        assert redirect(request("/about", options, german)) == {302, ["/en/about"], true}
        assert redirect(request("/news", options, french)) == {302, ["/en/news"], true}
      end
    end
  end

  describe "requests" do
    test "redirects only GET and HEAD" do
      assert redirect(request("/en/about", [], method: :head)) == {301, ["/about"], true}

      for method <- [:post, :put, :patch, :delete] do
        conn = request("/en/about", [], method: method)
        assert {conn.halted, conn.status} == {false, nil}, inspect(method)
      end

      conn =
        request("/about", [mode: :prefix_all],
          method: :post,
          session: %{"localize_locale" => "fr"}
        )

      assert served(conn) == {false, :fr, :session}
    end

    test "keeps the script name of a mounted application in the location" do
      conn = request("/en/about", [], conn: %{script_name: ["app"]})
      assert redirect(conn) == {301, ["/app/about"], true}
    end

    test "answers a locale parameter naming no supported locale with a 404" do
      exception =
        assert_raise LocalePrefix.NotFoundError, fn ->
          request("/blog/about", [], conn: %{path_params: %{"locale" => "blog"}})
        end

      assert Plug.Exception.status(exception) == 404
      assert Exception.message(exception) =~ ~s|"blog" is not a supported locale|

      for value <- ["fr-ca", "fra", ""] do
        assert_raise LocalePrefix.NotFoundError, fn ->
          request("/x/about", [], conn: %{path_params: %{"locale" => value}})
        end
      end
    end

    test "passes a locale parameter naming a supported locale, in any case" do
      for value <- ["fr", "FR", "de"] do
        conn = request("/#{value}/about", [], conn: %{path_params: %{"locale" => value}})
        assert {conn.halted, conn.status} == {false, nil}
      end

      assert redirect(request("/en/about", [], conn: %{path_params: %{"locale" => "en"}})) ==
               {301, ["/about"], true}
    end

    test "reads the parameter named by :param, or by PutLocale's :param" do
      assert_raise LocalePrefix.NotFoundError, fn ->
        request("/blog/about", [param: "lang"], conn: %{path_params: %{"lang" => "blog"}})
      end

      assert_raise LocalePrefix.NotFoundError, fn ->
        request("/blog/about", [],
          conn: %{path_params: %{"lang" => "blog"}},
          put_locale: [param: "lang"]
        )
      end

      conn = request("/blog/about", [], conn: %{path_params: %{"lang" => "blog"}})
      assert served(conn) == {false, :en, :default}
    end
  end

  describe "settings" do
    test "takes PutLocale's supported locales and default by default" do
      conn = request("/fr/about", [], put_locale: [supported: ["de", "fr"], default: "de"])

      assert LocalePrefix.get_settings(conn) == %{
               mode: :prefix_others,
               default: Localize.LanguageTag.new!("de"),
               supported: ["de", "fr"],
               param: "locale",
               exists?: nil
             }

      assert redirect(
               request("/de/about", [], put_locale: [supported: ["de", "fr"], default: "de"])
             ) ==
               {301, ["/about"], true}
    end

    test "takes the mode, supported locales and default from functions of the request" do
      options = [
        mode: {__MODULE__, :url_mode},
        supported: {__MODULE__, :site_locales, [[]]},
        default: "en"
      ]

      assert redirect(request("/about", options, conn: %{host: "all.example"})) ==
               {302, ["/en/about"], true}

      assert redirect(request("/en/about", options, conn: %{host: "other.example"})) ==
               {301, ["/about"], true}
    end

    test "logs and passes on a request when an option resolves to a value it cannot use" do
      for options <- [
            [mode: {__MODULE__, :bad_mode}],
            [default: "pt"],
            [supported: {__MODULE__, :bad_mode}]
          ] do
        log =
          capture_log(fn ->
            conn = request("/en/about", options)
            send(self(), {:conn, conn})
          end)

        assert_received {:conn, conn}
        assert {conn.halted, conn.status} == {false, nil}, inspect(options)
        assert log =~ "Localize.Plug.LocalePrefix", inspect(options)
      end
    end

    test "logs and passes on a request PutLocale has not run on" do
      log =
        capture_log(fn ->
          conn = LocalePrefix.call(conn(:get, "/en/about"), LocalePrefix.init([]))
          send(self(), {:conn, conn})
        end)

      assert_received {:conn, %Plug.Conn{halted: false, status: nil}}
      assert log =~ "Localize.Plug.PutLocale, which has not run"
    end

    test "refuses options it cannot use when the plug is initialised" do
      for options <- [
            %{},
            [mode: :prefix_some],
            [supported: "fr"],
            [exists?: fn _conn, _rest, _locale -> true end],
            [param: ""],
            [default: 42],
            [prefix: "x"]
          ] do
        assert_raise ArgumentError, ~r/Localize.Plug.LocalePrefix/, fn ->
          LocalePrefix.init(options)
        end
      end
    end
  end
end
