defmodule Localize.Plug.AcceptLanguage do
  @moduledoc """
  Parses the accept-language header if one is available and sets
  `conn.private[:localize_locale]` accordingly. The locale can
  be later retrieved by `Localize.Plug.AcceptLanguage.get_locale/1`.

  ## Options

  * `:no_match_log_level` determines the logging level for
    the case when no matching locale is configured to meet the
    user's request. The default is `:warning`. If set to `nil`
    then no logging is performed.

  ## Examples

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
  Returns the locale which is the best match for the provided
  accept-language header.

  """
  def best_match(nil, _options) do
    nil
  end

  def best_match(accept_language, options) do
    case Localize.AcceptLanguage.best_match(accept_language) do
      {:ok, locale} ->
        locale

      {:error, %Localize.UnknownLocaleError{} = exception} ->
        if options.log_level,
          do: Logger.log(options.log_level, Exception.message(exception))

        nil

      {:error, %{__exception__: true} = exception} ->
        Logger.warning(Exception.message(exception))
        nil

      {:error, {exception, reason}} ->
        Logger.warning("#{inspect(exception)}: #{reason}")
        nil
    end
  end

  @doc """
  Return the locale set by `Localize.Plug.AcceptLanguage`.

  """
  def get_locale(conn) do
    conn.private[:localize_locale]
  end
end
