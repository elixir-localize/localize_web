defmodule Localize.Plug do
  @moduledoc """
  Utility functions for setting the locale from the session for Localize and Gettext.

  The primary use case is in LiveView `on_mount` callbacks where the locale needs to be restored from the session that was set during the initial HTTP request by `Localize.Plug.PutLocale` and `Localize.Plug.PutSession`.

  """

  @session_key Localize.Plug.PutLocale.session_key()

  defmodule NoSessionLocaleError do
    @moduledoc """
    Returned by `Localize.Plug.put_locale_from_session/2` when the session has no locale.
    """

    defexception message: "No locale was found in the session"
  end

  @doc """
  Puts the locale from the session into the current process.

  Always sets the Localize process locale via `Localize.put_locale/1`. If Gettext backends are provided, the locale is also set on each backend.

  This function is useful to place in the `on_mount` callback for a LiveView.

  ### Arguments

  * `session` is any map, typically the map returned as part of the `conn` of a Phoenix or Plug request. A `session` is passed as the third parameter to the `on_mount` callback of a LiveView request.

  * `options` is a keyword list of options.

  ### Options

  * `:gettext` is a Gettext backend module or a list of Gettext backend modules on which the locale will be set. The default is `[]` (no Gettext backends).

  * `:session_key` is the session key the locale is read from, the `:session_key` given to `Localize.Plug.PutLocale`. The default is `"#{@session_key}"`.

  ### Returns

  * `{:ok, locale}` or

  * `{:error, exception}`. A session without a locale returns a
    `Localize.Plug.NoSessionLocaleError`.

  ### Examples

      iex> Localize.Plug.put_locale_from_session(session)
      iex> Localize.Plug.put_locale_from_session(session, gettext: MyApp.Gettext)
      iex> Localize.Plug.put_locale_from_session(session, gettext: [MyApp.Gettext, MyOtherApp.Gettext])

      # In a LiveView. A first visit has no locale in the session, so the
      # result is not matched on.
      def on_mount(:default, _params, session, socket) do
        _ = Localize.Plug.put_locale_from_session(session, gettext: MyApp.Gettext)
        {:cont, socket}
      end

  """
  @spec put_locale_from_session(map(), keyword()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, Exception.t()}

  def put_locale_from_session(session, options \\ [])

  def put_locale_from_session(session, options) when is_map(session) do
    with {:ok, gettext_backends} <- gettext_backends(options),
         {:ok, session_key} <- session_key(options),
         {:ok, locale} <- session_locale(session, session_key),
         {:ok, locale} <- Localize.validate_locale(locale) do
      Localize.put_locale(locale)
      Enum.each(gettext_backends, &put_gettext_locale(&1, locale))

      {:ok, locale}
    end
  end

  def put_locale_from_session(_session, _options) do
    {:error, %NoSessionLocaleError{}}
  end

  @doc """
  Returns the locale `Localize.Plug.PutLocale` resolved for a request, as the session of a live session.

  A connected LiveView cannot read the request, so it takes the locale from its session. This function is given as the `:session` of a `live_session`, where LiveView calls it with the `conn` of the request that renders the page and signs the result into that page. The locale then reaches `put_locale_from_session/2` in the `on_mount` callback without being written to the session cookie.

  That matters when `Localize.Plug.PutSession` is told, with its `:from` option, to store only a locale the visitor chose: a locale inferred from the `accept-language` header is not in the cookie, and without this function the LiveView would mount in the default locale. `Localize.Routes.localize_live_session/3` passes the locale of a localized route the same way, so this function is for live sessions that are not localized.

  ### Arguments

  * `conn` is the `t:Plug.Conn.t/0` of the request, which `Localize.Plug.PutLocale` has already been through.

  ### Returns

  * A map holding the locale as a string under the key `put_locale_from_session/2` reads, or

  * an empty map when no locale was set for the request.

  ### Examples

      live_session :default,
        on_mount: [MyAppWeb.LocaleLive],
        session: {Localize.Plug, :live_session_locale, []} do
        live "/dashboard", DashboardLive
      end

  """
  @spec live_session_locale(Plug.Conn.t()) :: %{optional(String.t()) => String.t()}
  def live_session_locale(conn) do
    case Localize.Plug.PutLocale.get_locale(conn) do
      %Localize.LanguageTag{} = locale ->
        %{Localize.Plug.PutLocale.get_session_key(conn) => Localize.LanguageTag.to_string(locale)}

      _other ->
        %{}
    end
  end

  # A locale that Gettext has no translations for is a configuration
  # mismatch rather than an error: the locale is still set for Localize,
  # and only the Gettext locale is left alone.
  defp put_gettext_locale(gettext_backend, locale) do
    case Localize.Locale.gettext_locale_id(locale, gettext_backend) do
      {:ok, gettext_locale} ->
        Gettext.put_locale(gettext_backend, gettext_locale)

      {:error, _reason} ->
        require Logger

        Logger.warning(
          "Localize.Plug.put_locale_from_session/2: locale #{inspect(locale.cldr_locale_id)} " <>
            "does not have a matching Gettext locale for backend #{inspect(gettext_backend)}. " <>
            "No Gettext locale has been set."
        )
    end
  end

  defp gettext_backends(options) do
    if Keyword.keyword?(options) do
      options
      |> Keyword.get(:gettext, [])
      |> List.wrap()
      |> Enum.find(&(not gettext_backend?(&1)))
      |> case do
        nil -> {:ok, List.wrap(Keyword.get(options, :gettext, []))}
        backend -> invalid_value(backend, "a Gettext backend module")
      end
    else
      invalid_value(options, "a keyword list of options")
    end
  end

  # `gettext_backends/1` has already checked that the options are a keyword list.
  defp session_key(options) do
    case Keyword.get(options, :session_key, @session_key) do
      session_key when is_binary(session_key) and byte_size(session_key) > 0 -> {:ok, session_key}
      other -> invalid_value(other, "a non-empty string session key")
    end
  end

  defp session_locale(session, session_key) do
    case Map.fetch(session, session_key) do
      {:ok, locale} -> {:ok, locale}
      :error -> {:error, %NoSessionLocaleError{}}
    end
  end

  defp gettext_backend?(backend) do
    is_atom(backend) and Code.ensure_loaded?(backend) and
      function_exported?(backend, :__gettext__, 1)
  end

  defp invalid_value(value, expected) do
    {:error, Localize.InvalidValueError.exception(value: value, expected: expected)}
  end
end
