defmodule Localize.Routes.LocalizedHelpers do
  @moduledoc """
  Generates a module that implements localised helpers.

  It introspects the generated helpers module and creates
  a wrapper function that translates (at compile time) the
  path segments.

  """

  @type locale_name :: String.t()
  @type url :: String.t()

  @known_suffixes ["path", "url"]

  @doc """
  For a given set of routes, define a LocalizedHelpers
  module that implements localized helpers.

  """
  def define(env, routes, opts \\ []) do
    localized_helper_module = Module.concat([env.module, LocalizedHelpers])
    helper_module = Module.concat([env.module, Helpers])
    gettext_backend = Module.get_attribute(env.module, :_gettext_backend)

    routes =
      Enum.reject(routes, fn {route, _exprs} ->
        is_nil(route.helper) or route.kind == :forward
      end)

    groups = Enum.group_by(routes, fn {route, _exprs} -> route.helper end)

    docs = Keyword.get(opts, :docs, true)
    localized_helpers = localized_helpers(groups)
    non_localized_helpers = non_localized_helpers(groups, helper_module)
    delegate_helpers = delegate_helpers(groups, helper_module, gettext_backend)
    other_delegates = other_delegates(helper_module)
    catch_all = catch_all(groups, helper_module)

    code =
      quote do
        @moduledoc unquote(docs) &&
                     """
                     Module with localized helpers generated from #{inspect(unquote(env.module))}.
                     """

        alias Localize.Routes.LocalizedHelpers

        unquote_splicing(localized_helpers)
        unquote_splicing(non_localized_helpers)
        unquote_splicing(delegate_helpers)
        unquote(other_delegates)
        unquote_splicing(catch_all)
        unquote_splicing(href_link_helpers(routes))
      end

    Module.create(localized_helper_module, code, line: env.line, file: env.file)
  end

  defp localized_helpers(groups) do
    for {_helper, helper_routes} <- groups,
        {_, [{route, exprs} | _]} <- routes_in_order(helper_routes),
        suffix <- @known_suffixes,
        localized_route?(route) do
      helper_fun_name = strip_locale(route.helper)
      {_bins, vars} = :lists.unzip(exprs.binding)

      quote do
        def unquote(:"#{helper_fun_name}_#{suffix}")(
              conn_or_endpoint,
              plug_opts,
              unquote_splicing(vars)
            ) do
          locale = Localize.get_locale()

          helper(
            unquote(helper_fun_name),
            unquote(suffix),
            locale,
            conn_or_endpoint,
            plug_opts,
            unquote_splicing(vars),
            %{}
          )
        end

        def unquote(:"#{helper_fun_name}_#{suffix}")(
              conn_or_endpoint,
              plug_opts,
              unquote_splicing(vars),
              params
            ) do
          locale = Localize.get_locale()

          helper(
            unquote(helper_fun_name),
            unquote(suffix),
            locale,
            conn_or_endpoint,
            plug_opts,
            unquote_splicing(vars),
            params
          )
        end
      end
    end
  end

  defp non_localized_helpers(groups, helper_module) do
    for {_helper, helper_routes} <- groups,
        {_, [{route, exprs} | _]} <- routes_in_order(helper_routes),
        suffix <- @known_suffixes,
        !localized_route?(route) do
      {_bins, vars} = :lists.unzip(exprs.binding)

      quote do
        def unquote(:"#{route.helper}_#{suffix}")(
              conn_or_endpoint,
              plug_opts,
              unquote_splicing(vars)
            ) do
          unquote(helper_module).unquote(:"#{route.helper}_#{suffix}")(
            conn_or_endpoint,
            plug_opts,
            unquote_splicing(vars)
          )
        end

        def unquote(:"#{route.helper}_#{suffix}")(
              conn_or_endpoint,
              plug_opts,
              unquote_splicing(vars),
              params
            ) do
          unquote(helper_module).unquote(:"#{route.helper}_#{suffix}")(
            conn_or_endpoint,
            plug_opts,
            unquote_splicing(vars),
            params
          )
        end
      end
    end
  end

  defp localized_route?(route) do
    Map.has_key?(route.private, :localize_locale)
  end

  defp delegate_helpers(groups, helper_module, gettext_backend) do
    all_locale_ids = Localize.Routes.locales_from_gettext(gettext_backend)

    for {_helper, helper_routes} <- groups,
        {_, [{route, exprs} | _]} <- routes_in_order(helper_routes),
        locale_id <- all_locale_ids,
        {:ok, locale} = Localize.validate_locale(locale_id),
        {:ok, gettext_locale} = Localize.Locale.gettext_locale_id(locale, gettext_backend),
        suffix <- @known_suffixes,
        helper_fun_name = strip_locale(route.helper, gettext_locale),
        helper_fun_name != route.helper do
      {_bins, vars} = :lists.unzip(exprs.binding)

      quote do
        @doc false
        def helper(
              unquote(helper_fun_name),
              unquote(suffix),
              %Localize.LanguageTag{cldr_locale_id: unquote(locale_id)},
              conn_or_endpoint,
              plug_opts,
              unquote_splicing(vars),
              params
            ) do
          unquote(helper_module).unquote(:"#{route.helper}_#{suffix}")(
            conn_or_endpoint,
            plug_opts,
            unquote_splicing(vars),
            params
          )
        end
      end
    end
  end

  defp catch_all(groups, helper_module) do
    for {helper, routes_and_exprs} <- groups,
        proxy_helper = strip_locale(helper),
        helper != proxy_helper do
      routes =
        routes_and_exprs
        |> Enum.map(fn {routes, exprs} ->
          {routes.plug_opts, Enum.map(exprs.binding, &elem(&1, 0))}
        end)
        |> Enum.sort()

      params_lengths =
        routes
        |> Enum.map(fn {_, bindings} -> length(bindings) end)
        |> Enum.uniq()

      binding_lengths = Enum.reject(params_lengths, &((&1 - 1) in params_lengths))

      catch_all_no_params =
        for length <- binding_lengths do
          binding = List.duplicate({:_, [], nil}, length)
          arity = length + 2

          quote do
            def helper(
                  unquote(proxy_helper),
                  suffix,
                  locale,
                  conn_or_endpoint,
                  action,
                  unquote_splicing(binding)
                ) do
              path(conn_or_endpoint, "/")

              raise_route_error(
                unquote(proxy_helper),
                suffix,
                unquote(arity),
                action,
                locale,
                unquote(helper_module),
                unquote(helper),
                []
              )
            end
          end
        end

      catch_all_params =
        for length <- params_lengths do
          binding = List.duplicate({:_, [], nil}, length)
          arity = length + 2

          quote do
            def helper(
                  unquote(proxy_helper),
                  suffix,
                  locale,
                  conn_or_endpoint,
                  action,
                  unquote_splicing(binding),
                  params
                ) do
              path(conn_or_endpoint, "/")

              raise_route_error(
                unquote(proxy_helper),
                suffix,
                unquote(arity + 1),
                action,
                locale,
                unquote(helper_module),
                unquote(helper),
                params
              )
            end

            defp raise_route_error(
                   unquote(proxy_helper),
                   suffix,
                   arity,
                   action,
                   locale,
                   unquote(helper_module),
                   unquote(helper),
                   params
                 ) do
              Localize.Routes.LocalizedHelpers.raise_route_error(
                __MODULE__,
                "#{unquote(proxy_helper)}_#{suffix}",
                arity,
                action,
                locale,
                unquote(helper_module),
                unquote(helper),
                unquote(Macro.escape(routes)),
                params
              )
            end
          end
        end

      quote do
        unquote_splicing(catch_all_no_params)
        unquote_splicing(catch_all_params)
      end
    end
  end

  defp other_delegates(helper_module) do
    quote do
      @doc """
      Generates the path information including any necessary prefix.
      """
      def path(data, path) do
        unquote(helper_module).path(data, path)
      end

      @doc """
      Generates the connection/endpoint base URL without any path information.
      """
      def url(data) do
        unquote(helper_module).url(data)
      end

      @doc """
      Generates path to a static asset given its file path.
      """
      def static_path(conn_or_endpoint, path) do
        unquote(helper_module).static_path(conn_or_endpoint, path)
      end

      @doc """
      Generates url to a static asset given its file path.
      """
      def static_url(conn_or_endpoint, path) do
        unquote(helper_module).static_url(conn_or_endpoint, path)
      end

      @doc """
      Generates an integrity hash to a static asset given its file path.
      """
      def static_integrity(conn_or_endpoint, path) do
        unquote(helper_module).static_integrity(conn_or_endpoint, path)
      end

      @doc """
      Generates HTML `link` tags for a given map of locale => URLs.

      This function generates `<link .../>` tags that should be placed
      in the `<head>` section of an HTML document to indicate the
      different language versions of a given page.

      """
      @spec hreflang_links(%{LocalizedHelpers.locale_name() => LocalizedHelpers.url()}) ::
              Phoenix.HTML.safe()

      def hreflang_links(url_map) do
        Localize.Routes.LocalizedHelpers.hreflang_links(url_map)
      end
    end
  end

  defp href_link_helpers(routes) do
    for {helper, routes_by_locale} <- helper_by_locale(routes),
        {vars, locales} <- routes_by_locale do
      if locales == [] do
        quiet_vars =
          Enum.map(vars, fn var ->
            quote do
              _ = unquote(var)
            end
          end)

        quote generated: true, location: :keep do
          def unquote(:"#{helper}_links")(conn_or_endpoint, plug_opts, unquote_splicing(vars)) do
            unquote_splicing(quiet_vars)
            Map.new()
          end
        end
      else
        quote generated: true, location: :keep do
          def unquote(:"#{helper}_links")(conn_or_endpoint, plug_opts, unquote_splicing(vars)) do
            for locale <- unquote(Macro.escape(locales)) do
              Localize.with_locale(locale, fn ->
                {
                  to_string(locale.cldr_locale_id),
                  unquote(:"#{helper}_url")(conn_or_endpoint, plug_opts, unquote_splicing(vars))
                }
              end)
            end
            |> Map.new()
          end
        end
      end
    end
  end

  defp routes_in_order(routes) do
    routes
    |> Enum.group_by(fn {_route, exprs} -> length(exprs.binding) end)
    |> Enum.sort()
  end

  def helper_by_locale(routes) do
    routes
    |> Enum.group_by(fn {route, _exprs} ->
      if localized_route?(route), do: strip_locale(route.helper), else: route.helper
    end)
    |> Enum.map(fn {helper, routes} ->
      {helper, routes_by_locale(routes)}
    end)
  end

  defp routes_by_locale(routes) do
    Enum.group_by(
      routes,
      fn {_route, exprs} -> elem(:lists.unzip(exprs.binding), 1) end,
      fn {route, _exprs} -> route.private[:localize_locale] end
    )
    |> Enum.map(fn
      {vars, [nil]} -> {vars, []}
      {vars, locales} -> {vars, Enum.uniq(locales)}
    end)
  end

  @doc false
  @dialyzer {:nowarn_function, raise_route_error: 9}
  def raise_route_error(mod, fun, arity, action, locale, helper_module, helper, routes, params) do
    cond do
      localized_fun_exists?(helper_module, helper, fun, arity) ->
        "no function clause for #{inspect(mod)}.#{fun}/#{arity} for locale #{inspect(locale)}"
        |> invalid_route_error(fun, routes)

      is_atom(action) and not Keyword.has_key?(routes, action) ->
        "no action #{inspect(action)} for #{inspect(mod)}.#{fun}/#{arity}"
        |> invalid_route_error(fun, routes)

      is_list(params) or is_map(params) ->
        "no function clause for #{inspect(mod)}.#{fun}/#{arity} and action #{inspect(action)}"
        |> invalid_route_error(fun, routes)

      true ->
        invalid_param_error(mod, fun, arity, action, routes)
    end
  end

  defp localized_fun_exists?(helper_module, helper, fun, arity) do
    suffix = String.split(fun, "_") |> Enum.reverse() |> hd()
    helper = :"#{helper}_#{suffix}"
    function_exported?(helper_module, helper, arity)
  end

  defp invalid_route_error(prelude, fun, routes) do
    suggestions =
      for {action, bindings} <- routes do
        bindings = Enum.join([inspect(action) | bindings], ", ")
        "\n    #{fun}(conn_or_endpoint, #{bindings}, params \\\\ [])"
      end

    raise ArgumentError,
          "#{prelude}. The following actions/clauses are supported:\n#{suggestions}"
  end

  defp invalid_param_error(mod, fun, arity, action, routes) do
    call_vars = Keyword.fetch!(routes, action)

    raise ArgumentError, """
    #{inspect(mod)}.#{fun}/#{arity} called with invalid params.
    The last argument to this function should be a keyword list or a map.
    For example:

        #{fun}(#{Enum.join(["conn", ":#{action}" | call_vars], ", ")}, page: 5, per_page: 10)

    It is possible you have called this function without defining the proper
    number of path segments in your router.
    """
  end

  @doc """
  Generates HTML `link` tags for a given map of locale => URLs.

  """
  @spec hreflang_links(%{locale_name() => url()}) :: Phoenix.HTML.safe()
  def hreflang_links(nil) do
    {:safe, []}
  end

  def hreflang_links(url_map) when is_map(url_map) do
    links =
      for {locale, url} <- url_map do
        {:safe, link} =
          PhoenixHTMLHelpers.Tag.tag(:link, href: url, rel: "alternate", hreflang: locale)

        link
      end
      |> Enum.intersperse(?\n)

    {:safe, links}
  end

  @doc false
  def strip_locale(helper, locale)

  def strip_locale(helper, %Localize.LanguageTag{} = locale) do
    case Localize.Locale.gettext_locale_id(locale, nil) do
      {:ok, gettext_locale} -> strip_locale(helper, gettext_locale)
      _ -> strip_locale_by_id(helper, locale.cldr_locale_id)
    end
  rescue
    _ -> strip_locale_by_id(helper, locale.cldr_locale_id)
  end

  def strip_locale(helper, nil) do
    helper
  end

  def strip_locale(nil = helper, _locale) do
    helper
  end

  def strip_locale(helper, locale_name) when is_binary(locale_name) do
    helper
    |> String.split(Regex.compile!("(_#{locale_name}_)|(_#{locale_name}$)"), trim: true)
    |> Enum.join("_")
  end

  defp strip_locale_by_id(helper, locale_id) when is_atom(locale_id) do
    locale_str = to_string(locale_id) |> String.downcase()
    strip_locale(helper, locale_str)
  end

  @doc false
  def strip_locale(helper) when is_binary(helper) do
    locale =
      helper
      |> String.split("_")
      |> Enum.reverse()
      |> hd()

    strip_locale(helper, locale)
  end
end
