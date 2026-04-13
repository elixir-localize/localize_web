defmodule Localize.Plug.AcceptLanguage do
  @moduledoc """
  Standalone plug that parses the `Accept-Language` header and sets `conn.private[:localize_locale]` to the best matching locale.

  The locale can be later retrieved by `Localize.Plug.AcceptLanguage.get_locale/1`. This plug is useful when you only need accept-language parsing without the full locale discovery pipeline of `Localize.Plug.PutLocale`.

  ### Options

  * `:no_match_log_level` determines the logging level for the case when no matching locale is configured to meet the user's request. The default is `:warning`. If set to `nil` then no logging is performed.

  ### Examples

      plug Localize.Plug.AcceptLanguage

  """

  import Plug.Conn
  require Logger

  @language_header "accept-language"
  @default_log_level :warning

  @doc false
  def init(options \\ []) do
    log_level = Keyword.get(options, :no_match_log_level, @default_log_level)
    %{log_level: log_level}
  end

  @doc false
  def call(conn, options) do
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

  * `options` is the plug options map containing `:log_level`.

  ### Returns

  * A `t:Localize.LanguageTag.t/0` or `nil`.

  """
  def best_match(nil, _options) do
    nil
  end

  def best_match(accept_language, options) do
    case Localize.AcceptLanguage.best_match(accept_language) do
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

  * A `t:Localize.LanguageTag.t/0` or `nil`.

  """
  def get_locale(conn) do
    conn.private[:localize_locale]
  end
end
