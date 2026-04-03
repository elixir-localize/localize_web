defmodule Localize.Plug do
  @moduledoc """
  Functions to support setting the locale for Localize and/or Gettext from the session.

  """

  @type application :: :localize | :gettext
  @type applications :: [application]

  @session_key Localize.Plug.PutLocale.session_key()

  @doc """
  Puts the locale from the session into the current process for
  `Localize` and/or `Gettext`.

  This function is useful to place in the `on_mount` callback
  for a LiveView.

  ### Arguments

  * `session` is any map, typically the map returned as part of
    the `conn` of a Phoenix or Plug request. A `session` is
    passed as the third parameter to the `on_mount` callback
    of a LiveView request.

  * `options` is a keyword list of options.

  ### Options

  * `:apps` is a list of applications for which the locale may
    be set. The valid options are `:localize` and `:gettext`.
    The default is `[:localize, :gettext]`.

  * `:gettext` is the Gettext backend module. Required if
    `:gettext` is in the `:apps` list.

  ### Returns

  * `{:ok, locale}` or

  * `{:error, {exception, reason}}`

  ### Examples

      iex> Localize.Plug.put_locale_from_session(session)
      iex> Localize.Plug.put_locale_from_session(session, apps: [:localize])
      iex> Localize.Plug.put_locale_from_session(session, apps: [:localize, :gettext], gettext: MyApp.Gettext)

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
    apps = Keyword.get(options, :apps, [:localize, :gettext])
    gettext_backend = Keyword.get(options, :gettext)

    with {:ok, locale} <- Localize.validate_locale(locale) do
      Enum.reduce_while(apps, nil, fn
        :localize, _acc ->
          {:cont, Localize.put_locale(locale)}

        :gettext, _acc ->
          if gettext_backend do
            case Localize.Locale.gettext_locale_id(locale, gettext_backend) do
              {:ok, gettext_locale} ->
                Gettext.put_locale(gettext_backend, gettext_locale)
                {:cont, {:ok, locale}}

              {:error, _reason} ->
                {:halt,
                 {:error,
                  {Localize.UnknownLocaleError,
                   "No gettext locale defined for #{inspect(locale)}"}}}
            end
          else
            {:cont, {:ok, locale}}
          end

        other, _acc ->
          raise ArgumentError,
                "Invalid application passed to Localize.Plug.put_locale_from_session/2. " <>
                  "Valid applications are :localize and :gettext. Found #{inspect(other)}"
      end)
    end
  end

  def put_locale_from_session(_session, _options) do
    {:error, {Localize.UnknownLocaleError, "No locale was found in the session"}}
  end
end
