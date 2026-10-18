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

  def put_locale_from_session(%{@session_key => locale}, options) do
    with {:ok, gettext_backends} <- gettext_backends(options),
         {:ok, locale} <- Localize.validate_locale(locale) do
      Localize.put_locale(locale)
      Enum.each(gettext_backends, &put_gettext_locale(&1, locale))

      {:ok, locale}
    end
  end

  def put_locale_from_session(_session, _options) do
    {:error, %NoSessionLocaleError{}}
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

  defp gettext_backend?(backend) do
    is_atom(backend) and Code.ensure_loaded?(backend) and
      function_exported?(backend, :__gettext__, 1)
  end

  defp invalid_value(value, expected) do
    {:error, Localize.InvalidValueError.exception(value: value, expected: expected)}
  end
end
