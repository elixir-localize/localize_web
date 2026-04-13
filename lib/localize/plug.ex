defmodule Localize.Plug do
  @moduledoc """
  Utility functions for setting the locale from the session for Localize and Gettext.

  The primary use case is in LiveView `on_mount` callbacks where the locale needs to be restored from the session that was set during the initial HTTP request by `Localize.Plug.PutLocale` and `Localize.Plug.PutSession`.

  """

  @session_key Localize.Plug.PutLocale.session_key()

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

  * `{:error, {exception, reason}}`

  ### Examples

      iex> Localize.Plug.put_locale_from_session(session)
      iex> Localize.Plug.put_locale_from_session(session, gettext: MyApp.Gettext)
      iex> Localize.Plug.put_locale_from_session(session, gettext: [MyApp.Gettext, MyOtherApp.Gettext])

      # In a LiveView
      def on_mount(:default, _params, session, socket) do
        {:ok, locale} = Localize.Plug.put_locale_from_session(session, gettext: MyApp.Gettext)
        {:cont, socket}
      end

  """
  @spec put_locale_from_session(map(), keyword()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, {module(), String.t()}}

  def put_locale_from_session(session, options \\ [])

  def put_locale_from_session(%{@session_key => locale}, options) do
    gettext_backends = normalize_gettext_backends(Keyword.get(options, :gettext, []))

    with {:ok, locale} <- Localize.validate_locale(locale) do
      Localize.put_locale(locale)

      Enum.each(gettext_backends, fn gettext_backend ->
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
      end)

      {:ok, locale}
    end
  end

  def put_locale_from_session(_session, _options) do
    {:error, {Localize.UnknownLocaleError, "No locale was found in the session"}}
  end

  defp normalize_gettext_backends(nil), do: []
  defp normalize_gettext_backends(backend) when is_atom(backend), do: [backend]
  defp normalize_gettext_backends(backends) when is_list(backends), do: backends
end
