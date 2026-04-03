defmodule Localize.VerifiedRoutes do
  @moduledoc """
  Implements localized verified routes using the `~q` sigil.

  Instead of configuring with `use Phoenix.VerifiedRoutes`,
  configure instead:

      use Localize.VerifiedRoutes,
        router: MyApp.Router,
        endpoint: MyApp.Endpoint,
        gettext: MyApp.Gettext

  When configured, the sigil `~q` is made available to express
  localized verified routes. Sigil `~p` remains available for
  non-localized verified routes.

  The `~q` sigil generates a `case` statement that dispatches
  to the appropriate localized `~p` route based on the current
  locale:

      # ~q"/users" generates:
      case Localize.get_locale().cldr_locale_id do
        :de -> ~p"/users_de"
        :en -> ~p"/users"
        :fr -> ~p"/users_fr"
      end

  ### Locale interpolation

  `:locale` is replaced with the CLDR locale name.
  `:language` is replaced with the CLDR language code.
  `:territory` is replaced with the CLDR territory code.

  """

  defmacro __using__(opts) do
    gettext = Keyword.fetch!(opts, :gettext)
    phoenix_opts = Keyword.drop(opts, [:gettext])

    quote location: :keep do
      use Phoenix.VerifiedRoutes, unquote(phoenix_opts)
      require unquote(gettext)

      import Phoenix.VerifiedRoutes, except: [url: 1, url: 2, url: 3]
      import Localize.VerifiedRoutes, only: :macros

      @_localize_gettext_backend unquote(gettext)
    end
  end

  @doc """
  Sigil_q implements localized verified routes.

  """
  defmacro sigil_q({:<<>>, _meta, _segments} = route, flags) do
    gettext = Module.get_attribute(__CALLER__.module, :_localize_gettext_backend)
    locale_ids = Localize.Routes.locales_from_gettext(gettext)

    case_clauses =
      Localize.VerifiedRoutes.sigil_q_case_clauses(route, flags, locale_ids, gettext)

    quote location: :keep do
      case Localize.get_locale().cldr_locale_id do
        unquote(case_clauses)
      end
    end
  end

  @doc """
  Generates the router url with localized route verification.

  """
  defmacro url({:sigil_q, _, [{:<<>>, _meta, _segments}, _flags]} = route) do
    expanded = Macro.expand(route, __CALLER__)
    wrap_sigil_p_in_url(expanded)
  end

  defmacro url(route) do
    quote do
      Phoenix.VerifiedRoutes.url(unquote(route))
    end
  end

  @doc """
  Generates the router url with localized route verification from the
  connection, socket, or URI.

  """
  defmacro url(
             conn_or_socket_or_endpoint_or_uri,
             {:sigil_q, _, [{:<<>>, _meta, _segments}, _]} = route
           ) do
    expanded = Macro.expand(route, __CALLER__)
    wrap_sigil_p_in_url(conn_or_socket_or_endpoint_or_uri, expanded)
  end

  defmacro url(conn_or_socket_or_endpoint_or_uri, route) do
    quote do
      Phoenix.VerifiedRoutes.url(unquote(conn_or_socket_or_endpoint_or_uri), unquote(route))
    end
  end

  @doc """
  Generates the router url with localized route verification from the
  connection, socket, or URI and router.

  """
  defmacro url(
             conn_or_socket_or_endpoint_or_uri,
             router,
             {:sigil_q, _, [{:<<>>, _meta, _segments}, _]} = route
           ) do
    expanded = Macro.expand(route, __CALLER__)
    wrap_sigil_p_in_url(conn_or_socket_or_endpoint_or_uri, router, expanded)
  end

  defmacro url(conn_or_socket_or_endpoint_or_uri, router, route) do
    quote do
      Phoenix.VerifiedRoutes.url(
        unquote(conn_or_socket_or_endpoint_or_uri),
        unquote(router),
        unquote(route)
      )
    end
  end

  @doc false
  def sigil_q_case_clauses(route, flags, locale_ids, gettext_backend) do
    for locale_id <- locale_ids do
      with {:ok, locale} <- Localize.validate_locale(locale_id),
           {:ok, _gettext_locale} <- Localize.Locale.gettext_locale_id(locale, gettext_backend) do
        translated_route =
          Localize.Routes.interpolate_and_translate_path(route, locale, gettext_backend)

        quote location: :keep do
          unquote(locale_id) -> sigil_p(unquote(translated_route), unquote(flags))
        end
      else
        {:error, _reason} ->
          IO.warn(
            "Locale #{inspect(locale_id)} has no associated gettext locale. " <>
              "Cannot translate #{inspect(route)}",
            []
          )

          nil
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&hd/1)
  end

  @doc false
  def wrap_sigil_p_in_url(ast) do
    Macro.postwalk(ast, fn
      {:->, meta, [locale, sigil_p]} ->
        url =
          quote do
            Phoenix.VerifiedRoutes.url(unquote(sigil_p))
          end

        {:->, meta, [locale, url]}

      other ->
        other
    end)
  end

  @doc false
  def wrap_sigil_p_in_url(conn_or_socket_or_endpoint_or_uri, ast) do
    Macro.prewalk(ast, fn
      {:->, meta, [locale, sigil_p]} ->
        url =
          quote do
            Phoenix.VerifiedRoutes.url(
              unquote(conn_or_socket_or_endpoint_or_uri),
              unquote(sigil_p)
            )
          end

        {:->, meta, [locale, url]}

      other ->
        other
    end)
  end

  @doc false
  def wrap_sigil_p_in_url(conn_or_socket_or_endpoint_or_uri, router, ast) do
    Macro.prewalk(ast, fn
      {:->, meta, [locale, sigil_p]} ->
        url =
          quote do
            Phoenix.VerifiedRoutes.url(
              unquote(conn_or_socket_or_endpoint_or_uri),
              unquote(router),
              unquote(sigil_p)
            )
          end

        {:->, meta, [locale, url]}

      other ->
        other
    end)
  end
end
