defmodule Localize.VerifiedRoutes do
  @moduledoc """
  Localized verified routes using the `~q` sigil.

  This module provides compile-time verified localized routes. Instead of configuring with `use Phoenix.VerifiedRoutes`, configure instead:

      use Localize.VerifiedRoutes,
        router: MyApp.Router,
        endpoint: MyApp.Endpoint,
        gettext: MyApp.Gettext

  When configured, the sigil `~q` is made available to express localized verified routes. Sigil `~p` remains available for non-localized verified routes.

  The `~q` sigil generates a `case` statement that dispatches to the appropriate localized `~p` route based on the current locale:

      # ~q"/users" generates:
      case Localize.get_locale().cldr_locale_id do
        :de -> ~p"/benutzer"
        :en -> ~p"/users"
        :fr -> ~p"/utilisateurs"
      end

  ### Locale Interpolation

  * `:locale` is replaced with the CLDR locale name.

  * `:language` is replaced with the CLDR language code.

  * `:territory` is replaced with the CLDR territory code.

  ### Rendering a path or URL in a specific locale

  `sigil_q` dispatches on the *current* process locale set by
  `Localize.put_locale/1`. When you need to render a link in a different
  locale without changing the process locale — for example, emitting a
  language switcher that lists the same page in every configured locale —
  use `path_for/2` and `url_for/2`:

      # In a template, with @locale bound from the request or session:
      <.link href={path_for(@locale, "/users")}>Users</.link>

      # Render every configured locale in one pass (language switcher):
      for locale <- [:en, :fr, :de] do
        path_for(locale, "/users")
      end

      url_for(:fr, "/users")
      #=> "http://localhost/users_fr"

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
  Implements the `~q` sigil for localized verified routes.

  Generates a `case` expression that dispatches to the translated `~p` route for the current locale. The route path is verified at compile time against the router.

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

  @doc ~S'''
  Generates a localized verified path in a specific locale.

  Unlike `sigil_q/2`, which dispatches on the *current* locale
  (`Localize.get_locale/0`), `path_for/2` lets the caller force a particular
  locale at the call site without changing the process-wide locale. This is
  useful when rendering links in multiple locales within a single template
  (for example, a language switcher).

  ### Arguments

  * `locale` is any locale id configured in the gettext backend. May be a
    literal atom or a runtime expression.

  * `route` is a string literal route (with optional `#{...}` interpolations),
    as accepted by `sigil_q/2`.

  ### Examples

      path_for(:fr, "/users")
      #=> "/utilisateurs"

      for locale <- [:en, :fr] do
        {locale, path_for(locale, "/users")}
      end
      #=> [en: "/users", fr: "/utilisateurs"]

  '''
  defmacro path_for(locale, route) do
    gettext = Module.get_attribute(__CALLER__.module, :_localize_gettext_backend)
    locale_ids = Localize.Routes.locales_from_gettext(gettext)
    route_ast = Localize.VerifiedRoutes.normalize_route_ast(route)

    case_clauses =
      Localize.VerifiedRoutes.sigil_q_case_clauses(route_ast, [], locale_ids, gettext)

    quote location: :keep do
      case unquote(locale) do
        unquote(case_clauses)
      end
    end
  end

  @doc ~S'''
  Generates a localized verified URL in a specific locale.

  Like `path_for/2` but returns a full URL via `Phoenix.VerifiedRoutes.url/1`.

  ### Arguments

  * `locale` is any locale id configured in the gettext backend.

  * `route` is a string literal route accepted by `sigil_q/2`.

  '''
  defmacro url_for(locale, route) do
    gettext = Module.get_attribute(__CALLER__.module, :_localize_gettext_backend)
    locale_ids = Localize.Routes.locales_from_gettext(gettext)
    route_ast = Localize.VerifiedRoutes.normalize_route_ast(route)

    case_clauses =
      Localize.VerifiedRoutes.sigil_q_case_clauses(route_ast, [], locale_ids, gettext)

    case_expr =
      quote location: :keep do
        case unquote(locale) do
          unquote(case_clauses)
        end
      end

    wrap_sigil_p_in_url(case_expr)
  end

  @doc false
  # Normalises the second arg of `path_for/2`/`url_for/2`. Accepts either a
  # plain string literal (passed straight through the macro as a binary) or
  # an interpolated-string AST (`{:<<>>, _, _}`) and returns the AST shape
  # expected by `sigil_q_case_clauses/4`.
  def normalize_route_ast(route) when is_binary(route) do
    {:<<>>, [], [route]}
  end

  def normalize_route_ast({:<<>>, _, _} = ast), do: ast

  def normalize_route_ast(other) do
    raise ArgumentError,
          "path_for/2 and url_for/2 expect a string literal route " <>
            "(optionally with \#{...} interpolations); got: #{Macro.to_string(other)}"
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
