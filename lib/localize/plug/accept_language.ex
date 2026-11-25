defmodule Localize.Plug.AcceptLanguage do
  @moduledoc """
  Standalone plug that parses the `Accept-Language` header and sets `conn.private[:localize_locale]` to the
  best matching locale.

  The locale can be later retrieved by `Localize.Plug.AcceptLanguage.get_locale/1`. This plug is useful
  when you only need accept-language parsing without the full locale discovery pipeline of `Localize.Plug.PutLocale`.

  The plug sets no `vary` response header, because it selects nothing: it records the locale and leaves its
  use to the application. An application that chooses content from the result should send
  `vary: accept-language`, so that a shared cache does not serve one visitor's language to another.

  ### Options

  * `:no_match_log_level` determines the logging level for the case when no matching locale is configured to meet the user's
    request. The default is `:warning`. If set to `nil` then no logging is performed.

  * `:supported` is the list of locales the header is matched against, as for `Localize.AcceptLanguage.best_match/2`. It may also be a `{Module, function}` or `{Module, function, args}` tuple, whose function is called with the `conn` and the plug's options, followed by `args`, and returns the list, for an application that learns its locales from the request: a site found from the host, whose languages are kept in a database. The locale set is then the entry that matched. The default is the locales configured for Localize.

  ### Examples

      plug Localize.Plug.AcceptLanguage

      plug Localize.Plug.AcceptLanguage, supported: {MyApp.Sites, :locales}

  """

  import Plug.Conn
  require Logger

  @language_header "accept-language"
  @default_log_level :warning

  @doc false
  def init(options \\ []) do
    log_level = Keyword.get(options, :no_match_log_level, @default_log_level)
    supported = Localize.Plug.PutLocale.supported_option(Keyword.get(options, :supported))
    %{log_level: log_level, supported: supported}
  end

  @doc false
  def call(conn, options) do
    options = %{options | supported: Localize.Plug.PutLocale.supported_locales(conn, options)}

    case get_req_header(conn, @language_header) do
      [accept_language | _] ->
        put_private(conn, :localize_locale, best_match(accept_language, options))

      [] ->
        put_private(conn, :localize_locale, nil)
    end
  end

  @doc """
  Returns the best matching locale for the provided accept-language header value.

  ### Arguments

  * `accept_language` is an accept-language header string or `nil`.

  * `options` is the plug options map containing `:log_level` and, optionally, `:supported`, a list of locales to match against. Without `:supported`, or with `nil`, the header is matched against the locales configured for Localize.

  ### Returns

  * A `t:Localize.LanguageTag.t/0` or `nil`.

  ### Examples

      iex> options = Localize.Plug.AcceptLanguage.init([])
      iex> Localize.Plug.AcceptLanguage.best_match("fr, en;q=0.5", options).cldr_locale_id
      :fr

  """
  def best_match(nil, _options) do
    nil
  end

  def best_match(accept_language, options) do
    supported = Map.get(options, :supported)

    case Localize.AcceptLanguage.best_match(accept_language, supported: supported) do
      {:ok, locale} ->
        locale

      {:error, %Localize.UnknownLocaleError{} = exception} ->
        if options.log_level do
          Logger.log(
            options.log_level,
            "Localize.Plug.AcceptLanguage: no matching locale found " <>
              "for accept-language header #{inspect(accept_language)}. " <>
              Exception.message(exception)
          )
        end

        nil

      {:error, %{__exception__: true} = exception} ->
        Logger.warning(
          "Localize.Plug.AcceptLanguage: error parsing accept-language header " <>
            "#{inspect(accept_language)}. #{Exception.message(exception)}"
        )

        nil
    end
  end

  @doc """
  Returns the locale set by `Localize.Plug.AcceptLanguage`.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0`.

  ### Returns

  * A `t:Localize.LanguageTag.t/0`, or `nil` when no locale was set or `conn` is not a `t:Plug.Conn.t/0`.

  ### Examples

      iex> conn =
      ...>   Plug.Test.conn(:get, "/")
      ...>   |> Plug.Conn.put_req_header("accept-language", "fr, en;q=0.5")
      ...>   |> Localize.Plug.AcceptLanguage.call(Localize.Plug.AcceptLanguage.init([]))
      iex> Localize.Plug.AcceptLanguage.get_locale(conn).cldr_locale_id
      :fr

  """
  def get_locale(%Plug.Conn{private: private}) do
    private[:localize_locale]
  end

  def get_locale(_conn) do
    nil
  end
end
