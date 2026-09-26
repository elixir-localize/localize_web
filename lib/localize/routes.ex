defmodule Localize.Routes do
  @moduledoc """
  Compile-time route localization for Phoenix routers.

  When `use`d, this module provides a `localize/1` macro that wraps standard Phoenix route macros such as `get/3`, `put/3` and `resources/3`, generating localized versions for each locale defined in a Gettext backend module.

  Path segments are translated at compile time using Gettext's `dgettext/3` with the `"routes"` domain. The translated paths are added to the standard Phoenix routing framework alongside the original routes.

  ### Configuration

  A Gettext backend module is required. Path segments (the parts between `/`) are translated at compile time. Therefore localization can only be applied to locales that are defined in a Gettext backend module.

  For example:

      defmodule MyApp.Router do
        use Phoenix.Router
        use Localize.Routes, gettext: MyApp.Gettext

        localize do
          get "/pages/:page", PageController, :show
          resources "/users", UserController
        end
      end

  ### Interpolating Locale Data

  A route may be defined with elements of the locale interpolated into it. These interpolations are specified using the normal `\#{}` interpolation syntax. However since route translation occurs at compile time only the following interpolations are supported:

  * `locale` will interpolate the CLDR locale name.

  * `language` will interpolate the language code.

  * `territory` will interpolate the territory code.

  ### Localized Helpers

  A `LocalizedHelpers` module is generated at compile time. Assuming the router module is called `MyApp.Router` then the full name of the localized helper module is `MyApp.Router.LocalizedHelpers`.

  Localized helpers can be disabled by adding `helpers: false` to the `use Localize.Routes` line in your router module.

  ### Translations

  In order for routes to be localized, translations must be provided for each path segment. This translation is performed by `Gettext.dgettext/3` with the domain `"routes"`. Therefore for each configured locale, a `routes.po` file is required containing the path segment translations for that locale.

  """

  @domain "routes"
  @path_separator "/"
  @interpolate ":"

  @localizable_verbs [
    :resources,
    :get,
    :put,
    :patch,
    :post,
    :delete,
    :options,
    :head,
    :connect,
    :live
  ]

  defmacro __using__(options) do
    gettext_backend = Keyword.fetch!(options, :gettext)
    helpers? = Keyword.get(options, :helpers, true)

    # Expand module aliases to atoms at compile time
    gettext_backend = Macro.expand(gettext_backend, __CALLER__)

    caller = __CALLER__.module

    Module.put_attribute(caller, :_helpers?, helpers?)
    Module.put_attribute(caller, :_gettext_backend, gettext_backend)

    quote location: :keep do
      require Gettext.Macros
      import Localize.Routes, only: :macros
      @before_compile Localize.Routes
    end
  end

  @doc false
  def localizable_verbs do
    @localizable_verbs
  end

  @doc false
  defmacro __before_compile__(env) do
    alias Localize.Routes.LocalizedHelpers
    generate_helpers? = Module.get_attribute(env.module, :_helpers?)
    routes = env.module |> Module.get_attribute(:phoenix_routes) |> Enum.reverse()
    localized_routes = Localize.Routes.routes(routes)
    forwards = env.module |> Module.get_attribute(:phoenix_forwards)

    Module.delete_attribute(env.module, :phoenix_routes)
    Module.register_attribute(env.module, :phoenix_routes, [])

    Module.put_attribute(
      env.module,
      :phoenix_routes,
      Localize.Routes.delete_original_path(routes)
    )

    # `Phoenix.Router.Route.exprs/1` gained a second argument in later
    # Phoenix releases. `apply/3` is what lets one build support both
    # arities — a direct call to the absent one would not compile.
    routes_with_exprs =
      if function_exported?(Phoenix.Router.Route, :exprs, 2) do
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        Enum.map(routes, &{&1, apply(Phoenix.Router.Route, :exprs, [&1, forwards])})
      else
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        Enum.map(routes, &{&1, apply(Phoenix.Router.Route, :exprs, [&1])})
      end

    if generate_helpers? do
      helpers_moduledoc = Module.get_attribute(env.module, :helpers_moduledoc)
      LocalizedHelpers.define(env, routes_with_exprs, docs: helpers_moduledoc)
    end

    quote location: :keep do
      defmodule LocalizedRoutes do
        @moduledoc """
        This module exists only to host route definitions.

        Localised routes can be printed by leveraging
        the `phx.routes` mix task.  For example:

            % mix phx.routes #{inspect(__MODULE__)}

        """

        def __routes__ do
          unquote(Macro.escape(localized_routes))
        end

        # `mix phx.routes` renders through `Phoenix.Router.ConsoleFormatter`,
        # which calls `formatted_routes/1` and `__helpers__/0` on whatever
        # module it is given. This module only hosts route definitions — it
        # is not a router and gets none of `Phoenix.Router`'s callbacks — so
        # both are defined here. `__formatted_routes__/1` postdates Phoenix
        # 1.7, which this library still supports, hence the export check
        # rather than a direct call that would warn on the older release.
        def formatted_routes(_options) do
          # `Code.ensure_loaded?/1` first: `function_exported?/3` answers
          # false for a module that merely has not been loaded yet, which
          # would silently fall back to the raw routes — and those lack
          # the `:label` the formatter expects.
          if Code.ensure_loaded?(Phoenix.Router) and
               function_exported?(Phoenix.Router, :__formatted_routes__, 1) do
            # credo:disable-for-next-line Credo.Check.Refactor.Apply
            apply(Phoenix.Router, :__formatted_routes__, [__MODULE__])
          else
            __routes__()
          end
        end

        # Delegated so the helper column matches the router these routes
        # were generated from.
        def __helpers__ do
          unquote(env.module).__helpers__()
        end
      end
    end
  end

  @doc false
  def delete_original_path(routes) do
    Enum.map(routes, fn route ->
      private = Map.delete(route.private, :original_path)
      Map.put(route, :private, private)
    end)
  end

  @doc """
  Generates localised routes for each locale defined in the
  configured Gettext backend.

  This macro is intended to wrap a series of standard route
  definitions in a `do` block. For example:

      localize do
        get "/pages/:page", PageController, :show
        resources "/users", UsersController
      end

  """
  defmacro localize(do: {:__block__, meta, routes}) do
    translated_routes =
      for route <- routes do
        quote location: :keep do
          localize(do: unquote(route))
        end
      end

    {:__block__, meta, translated_routes}
  end

  defmacro localize(do: route) do
    gettext_backend = Module.get_attribute(__CALLER__.module, :_gettext_backend)
    locale_ids = locales_from_gettext(gettext_backend)

    quote location: :keep do
      require unquote(gettext_backend)
      localize(unquote(locale_ids), do: unquote(route))
    end
  end

  @doc """
  Generates localised routes for each locale provided.

  This macro is intended to wrap a series of standard route
  definitions in a `do` block. For example:

      localize [:en, :fr] do
        get "/pages/:page", PageController, :show
        resources "/users", UsersController
      end

  """
  defmacro localize(locale_ids, do: {:__block__, meta, routes})
           when is_list(locale_ids) do
    translated_routes =
      for route <- routes do
        quote location: :keep do
          localize(unquote(locale_ids), do: unquote(route))
        end
      end

    {:__block__, meta, translated_routes}
  end

  defmacro localize(locale_ids, do: route) when is_list(locale_ids) do
    gettext_backend = Module.get_attribute(__CALLER__.module, :_gettext_backend)

    locale_ids
    |> Enum.map(&localized_route(&1, route, gettext_backend))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&canonical_route/1)
  end

  # Single locale (string or atom) - wrap in list
  defmacro localize(locale, do: block) when is_binary(locale) or is_atom(locale) do
    quote location: :keep do
      localize([unquote(locale)], do: unquote(block))
    end
  end

  defmacro localize(locale, do: {:__block__, meta, routes}) do
    translated_routes =
      for route <- routes do
        quote location: :keep do
          localize(unquote(locale), do: unquote(route))
        end
      end

    {:__block__, meta, translated_routes}
  end

  defmacro localize(locale, do: route) do
    quote location: :keep do
      localize(unquote(locale), unquote(route))
    end
  end

  # Rewrite nested resources; guard against infinite recursion
  defmacro localize(locale, {:resources, _, [path, controller, [do: {fun, _, _}] = nested]})
           when fun != :localize do
    nested = localize_nested_resources(locale, nested)

    quote location: :keep do
      localize unquote(locale) do
        resources unquote(path), unquote(controller) do
          unquote(nested)
        end
      end
    end
  end

  # Do the actual translations - locale is {%LanguageTag{}, gettext_locale_string}
  defmacro localize({locale, gettext_locale}, {verb, meta, [path | args]})
           when verb in @localizable_verbs do
    gettext_backend = Module.get_attribute(__CALLER__.module, :_gettext_backend)
    do_localize(:private, {locale, gettext_locale}, gettext_backend, {verb, meta, [path | args]})
  end

  # If the verb is unsupported for localization
  defmacro localize(_locale, {verb, _meta, [path | args]}) do
    {args, []} = Code.eval_quoted(args)
    args = Enum.map_join(args, ", ", &inspect/1)

    raise ArgumentError,
          """
          Invalid route for localization: #{verb} #{inspect(path)}, #{inspect(args)}
          Allowed localizable routes are #{inspect(@localizable_verbs)}
          """
  end

  # Expands one locale into a `localize/2` call carrying both the
  # resolved language tag and its Gettext locale. A locale with no
  # Gettext translations is warned about and skipped; an invalid locale
  # identifier is a mistake in the router and raises.
  defp localized_route(locale_id, route, gettext_backend) do
    case Localize.validate_locale(locale_id) do
      {:ok, locale} -> gettext_localized_route(locale, locale_id, route, gettext_backend)
      {:error, exception} -> raise exception
    end
  end

  defp gettext_localized_route(locale, locale_id, route, gettext_backend) do
    case Localize.Locale.gettext_locale_id(locale, gettext_backend) do
      {:ok, gettext_locale} ->
        quote do
          localize(
            {unquote(Macro.escape(locale)), unquote(gettext_locale)},
            unquote(route)
          )
        end

      {:error, _reason} ->
        warn_no_gettext_locale(locale_id, route)
    end
  end

  defp do_localize(field, {locale, gettext_locale}, gettext_backend, {verb, meta, [path | args]}) do
    locale = eval_locale(locale)

    {original_path, _} = escape_interpolation(path) |> Code.eval_quoted()

    translated_path =
      path
      |> interpolate(locale)
      |> combine_string_segments()
      |> :erlang.iolist_to_binary()
      |> translate_path(gettext_locale, gettext_backend)

    args =
      add_to_route(args, field, :localize_locale, locale)
      |> add_to_route(:private, :original_path, original_path)
      |> add_to_route(:private, :localize_gettext_locale, gettext_locale)
      |> localise_helper(verb, gettext_locale)

    quote location: :keep do
      unquote({verb, meta, [translated_path | args]})
    end
  end

  defp eval_locale({:%{}, _, _} = ast) do
    {locale, []} = Code.eval_quoted(ast)
    locale
  end

  defp eval_locale(%Localize.LanguageTag{} = locale), do: locale

  defp localize_nested_resources(locale, nested) do
    Macro.postwalk(nested, fn
      {:resources, _, [_path, _meta, _args, [do: {:resources, _, _}]]} = resources ->
        quote location: :keep do
          localize unquote(locale) do
            unquote(resources)
          end
        end

      {:resources, _, [_path, _meta, [do: {:resources, _, _}]]} = resources ->
        quote location: :keep do
          localize unquote(locale) do
            unquote(resources)
          end
        end

      {:resources, _, _} = route ->
        quote location: :keep do
          localize(unquote(locale), unquote(route))
        end

      other ->
        other
    end)
  end

  @meta_locales [:und, :"en-001"]

  @doc false
  def locales_from_gettext(gettext_backend) do
    gettext_backend
    |> Gettext.known_locales()
    |> Enum.map(&Localize.validate_locale/1)
    |> Enum.filter(fn
      {:ok, %{cldr_locale_id: id}} when id not in @meta_locales -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, locale} -> locale.cldr_locale_id end)
    |> Enum.uniq()
  end

  @doc false
  # The locale whose localized routes serve `locale`: `locale` itself
  # when routes exist for it, otherwise the default locale. A locale can
  # be valid without routes when it is supported but has no Gettext
  # translations, and `Localize.Plug.PutLocale` accepts such a locale.
  def route_locale(locale, locale_ids) do
    locale = validate_locale!(locale)

    if locale.cldr_locale_id in locale_ids do
      locale
    else
      default = Localize.default_locale()

      if default.cldr_locale_id in locale_ids do
        default
      else
        raise ArgumentError,
              "No localized routes for #{inspect(locale.cldr_locale_id)} or for the " <>
                "default locale #{inspect(default.cldr_locale_id)}. " <>
                "Localized routes exist for #{inspect(locale_ids)}"
      end
    end
  end

  defp validate_locale!(%Localize.LanguageTag{cldr_locale_id: id} = locale) when not is_nil(id),
    do: locale

  defp validate_locale!(locale) do
    case Localize.validate_locale(locale) do
      {:ok, locale} -> locale
      {:error, exception} -> raise exception
    end
  end

  @doc false
  def interpolate_and_translate_path(path, locale, gettext_backend) do
    {:ok, gettext_locale} = Localize.Locale.gettext_locale_id(locale, gettext_backend)

    path
    |> interpolate(locale)
    |> translate_path_now(locale, gettext_locale, gettext_backend)
    |> merge_literal_segments()
  end

  @doc false
  def interpolate(path, locale) do
    Macro.prewalk(path, fn
      # Replace the whole `::binary` wrapper, not merely the
      # `Kernel.to_string/1` call inside it. Substituting only the inner
      # call leaves `<<"/", "en"::binary, "/users">>`, and Phoenix's route
      # verifier matches a dynamic segment only as a `::binary` around a
      # `Kernel.to_string/1` call — a literal inside one matches none of
      # its clauses and reaches the catch-all that raises "a dynamic ~p
      # interpolation must follow a static segment".
      {:"::", _meta, [{{:., _, [Kernel, :to_string]}, _, [{token, _, _}]}, {:binary, _, _}]}
      when token in [:locale, :language, :territory] ->
        interpolated_value(token, locale)

      # The same tokens unwrapped, for callers that walk a path fragment
      # rather than a whole binary construction.
      {{:., _, [Kernel, :to_string]}, _, [{token, _, _}]}
      when token in [:locale, :language, :territory] ->
        interpolated_value(token, locale)

      other ->
        other
    end)
  end

  defp interpolated_value(:locale, locale),
    do: locale.cldr_locale_id |> to_string() |> String.downcase()

  defp interpolated_value(:language, locale),
    do: locale.language |> to_string() |> String.downcase()

  defp interpolated_value(:territory, locale),
    do: locale.territory |> to_string() |> String.downcase()

  # Folds adjacent literal segments into one binary, leaving genuine
  # runtime interpolations untouched. Once a locale token has been
  # substituted the path holds consecutive literals — `["/", "en",
  # "/users"]` — and Phoenix accepts a static segment only when it begins
  # with "/", so the pieces have to be joined into `["/en/users"]` before
  # `sigil_p` sees them.
  defp merge_literal_segments({:<<>>, meta, segments}) do
    {:<<>>, meta, merge_literals(segments)}
  end

  defp merge_literal_segments(other), do: other

  defp merge_literals([first, second | rest]) when is_binary(first) and is_binary(second) do
    merge_literals([first <> second | rest])
  end

  defp merge_literals([segment | rest]), do: [segment | merge_literals(rest)]
  defp merge_literals([]), do: []

  @doc false
  def translate_path_now(path, locale, gettext_locale, gettext_backend) do
    Macro.prewalk(path, fn segment ->
      translate_segment_now(locale, gettext_locale, gettext_backend, segment)
    end)
  end

  defp translate_segment_now(_locale, _gettext_locale, _backend, "" = segment), do: segment

  defp translate_segment_now(_locale, _gettext_locale, _backend, @interpolate <> _rest = segment),
    do: segment

  defp translate_segment_now(_locale, _gettext_locale, _backend, segment)
       when not is_binary(segment),
       do: segment

  defp translate_segment_now(locale, gettext_locale, gettext_backend, segment)
       when is_binary(segment) do
    segment
    |> String.split("/")
    |> translate_segment_parts(locale, gettext_locale, gettext_backend)
    |> Enum.join("/")
  end

  defp translate_segment_parts([last_part], locale, gettext_locale, gettext_backend) do
    [last_part | rest] = Regex.split(~r/[#\?]/, last_part, include_captures: true)

    [translate_segment_part(last_part, locale, gettext_locale, gettext_backend) | rest]
    |> :erlang.iolist_to_binary()
    |> List.wrap()
  end

  defp translate_segment_parts([part | rest], locale, gettext_locale, gettext_backend) do
    [
      translate_segment_part(part, locale, gettext_locale, gettext_backend)
      | translate_segment_parts(rest, locale, gettext_locale, gettext_backend)
    ]
  end

  defp translate_segment_part("", _locale, _gettext_locale, _backend), do: ""

  defp translate_segment_part(":locale", locale, _gettext_locale, _backend) do
    to_string(locale.cldr_locale_id) |> String.downcase()
  end

  defp translate_segment_part(":territory", locale, _gettext_locale, _backend) do
    to_string(locale.territory) |> String.downcase()
  end

  defp translate_segment_part(":language", locale, _gettext_locale, _backend) do
    to_string(locale.language) |> String.downcase()
  end

  defp translate_segment_part(part, _locale, gettext_locale, gettext_backend) do
    Gettext.put_locale(gettext_backend, gettext_locale)
    Gettext.dgettext(gettext_backend, @domain, part)
  end

  # Since we are doing compile-time translation of the
  # path, the path needs to be a string (not an expression).
  # This function attempts to combine the segments and
  # raises an exception if a string cannot be created.

  defp combine_string_segments([]) do
    []
  end

  defp combine_string_segments(a) when is_binary(a) do
    [a]
  end

  defp combine_string_segments({:"::", _, [a, {:binary, _, _}]}) do
    [a]
  end

  defp combine_string_segments({:<<>>, _, [a | b]}) do
    [combine_string_segments(a) | combine_string_segments(b)]
  end

  defp combine_string_segments({:<>, _, [a, b]}) do
    [combine_string_segments(a), combine_string_segments(b)]
  end

  defp combine_string_segments([a | rest]) do
    [combine_string_segments(a) | combine_string_segments(rest)]
  end

  defp combine_string_segments(ast) do
    raise ArgumentError,
          """
          The path argument to a localized route must be a binary that can be resolved at compile time. Found:

          #{Macro.to_string(ast)}
          """
  end

  @doc false
  def translate_path(path, gettext_locale, gettext_backend) do
    path
    |> String.split(@path_separator)
    |> Enum.map(&translate_part(gettext_locale, gettext_backend, &1))
    |> reduce_parts()
  end

  defp translate_part(_locale, _backend, "" = part), do: part
  defp translate_part(_locale, _backend, @interpolate <> _rest = part), do: part

  defp translate_part(gettext_locale, gettext_backend, part) do
    domain = @domain

    quote do
      Gettext.put_locale(unquote(gettext_backend), unquote(gettext_locale))

      Gettext.Macros.dgettext_with_backend(
        unquote(gettext_backend),
        unquote(domain),
        unquote(part)
      )
    end
  end

  defp reduce_parts([]), do: []
  defp reduce_parts([a, b]), do: {:<>, [], [a, {:<>, [], ["/", b]}]}
  defp reduce_parts([a | b]), do: {:<>, [], [a, {:<>, [], ["/", reduce_parts(b)]}]}

  # Localise the helper name for a verb (except resources)
  defp localise_helper(args, verb, locale) when verb not in [:resources] do
    [{_aliases, _meta, controller} | _rest] = args
    configured_helper = get_option(args, :as)
    helper = helper_name(controller, locale, configured_helper)
    put_option(args, :as, String.to_atom(helper))
  end

  defp localise_helper(args, :resources, locale) do
    case args do
      [controller, options, do_block] ->
        {_aliases, _meta, controller_name} = controller
        configured_helper = get_option(args, :as)

        options =
          options
          |> Keyword.put(:name, name(controller_name))
          |> Keyword.put(:as, helper_name(controller_name, locale, configured_helper))

        [controller, options, do_block]

      [controller, _options] ->
        {_aliases, _meta, controller} = controller
        configured_helper = get_option(args, :as)
        helper = helper_name(controller, locale, configured_helper)
        put_option(args, :as, helper)
    end
  end

  defp name(controller) do
    Phoenix.Naming.resource_name(Module.concat(controller), "Controller")
  end

  defp helper_name(controller, locale, nil) do
    Phoenix.Naming.resource_name(Module.concat(controller), "Controller") <> "_" <> locale
  end

  defp helper_name(_controller, locale, configured_helper) do
    to_string(configured_helper) <> "_" <> locale
  end

  defp get_option([_controller, _action, options], field) do
    Keyword.get(options, field)
  end

  defp get_option([_controller, options], field) do
    Keyword.get(options, field)
  end

  defp put_option([controller, action, options], field, value) do
    [controller, action, [{field, value} | options]]
  end

  defp put_option([controller, options], field, value) do
    [controller, [{field, value} | options]]
  end

  defp warn_no_gettext_locale(locale_id, route) do
    {verb, _meta, [path, _controller | _args]} = route

    IO.warn(
      "No known gettext locale for #{inspect(locale_id)}. " <>
        "No #{inspect(locale_id)} localized routes will be generated " <>
        "for #{inspect(verb)} #{Macro.to_string(path)}",
      []
    )

    nil
  end

  @doc false
  def add_to_route(args, field, key, value) do
    case Enum.reverse(args) do
      [[do: block], last | rest] ->
        last
        |> put_route(field, key, value)
        |> combine(rest, do: block)
        |> Enum.reverse()

      [last | rest] ->
        last
        |> put_route(field, key, value)
        |> combine(rest)
        |> Enum.reverse()

      [] = last ->
        put_route(last, field, key, value)
    end
  end

  defp combine(first, rest) when is_list(first) and is_list(rest), do: first ++ rest
  defp combine(first, rest), do: [first | rest]

  defp combine(first, rest, block) when is_list(first) and is_list(rest),
    do: [block | first ++ rest]

  defp combine(first, rest, block), do: [block, first | rest]

  defp put_route([{first, _value} | _rest] = options, field, key, value) when is_atom(first) do
    {field_content, options} = Keyword.pop(options, field)
    options = [Keyword.put(options, field, put_value(field_content, key, value))]

    quote do
      unquote(options)
    end
  end

  defp put_route(last, field, key, value) do
    options =
      quote do
        [{unquote(field), %{unquote(key) => unquote(Macro.escape(value))}}]
      end

    [options, last]
  end

  defp put_value(nil, key, value) do
    quote do
      %{unquote(key) => unquote(Macro.escape(value))}
    end
  end

  defp put_value({:%{}, meta, key_values}, key, value) do
    {:%{}, meta, [{key, Macro.escape(value)} | key_values]}
  end

  defp canonical_route({verb, meta, [path, controller, action | _args]}) when is_atom(action) do
    {verb, meta, [path, controller, action]}
  end

  defp canonical_route({verb, meta, [path, controller | _args]}) do
    {verb, meta, [path, controller]}
  end

  defp canonical_route({:localize, _, [[do: {verb, meta, [path, controller, action]}]]})
       when is_atom(action) do
    {verb, meta, [path, controller, action]}
  end

  @route_keys [:verb, :path, :plug, :plug_opts, :helper, :metadata]

  @doc false
  def routes(routes) do
    routes
    |> Enum.map(&strip_locale_from_helper/1)
    |> Enum.map(&add_locales_to_metadata/1)
    |> group_locales_by_path_helper_verb()
    |> Enum.map(&Map.take(&1, @route_keys))
  end

  defp group_locales_by_path_helper_verb([]) do
    []
  end

  defp group_locales_by_path_helper_verb([
         %{path: path, helper: helper, verb: verb} = first,
         %{path: path, helper: helper, verb: verb} = second | rest
       ]) do
    locales = Enum.uniq([locale_from_args(second) | first.metadata.locales]) |> Enum.sort()
    metadata = Map.put(first.metadata, :locales, locales)
    group_locales_by_path_helper_verb([%{first | metadata: metadata} | rest])
  end

  defp group_locales_by_path_helper_verb([first | rest]) do
    [first | group_locales_by_path_helper_verb(rest)]
  end

  defp add_locales_to_metadata(%{private: %{localize_locale: locale}} = route) do
    metadata = Map.put(route.metadata, :locales, [locale])
    %{route | metadata: metadata}
  end

  defp add_locales_to_metadata(other) do
    other
  end

  defp strip_locale_from_helper(%{private: %{localize_locale: locale}} = route) do
    do_strip_locale_from_helper(route, locale)
  end

  defp strip_locale_from_helper(%{private: %{}} = other) do
    other
  end

  defp strip_locale_from_helper(%{helper: nil} = route) do
    route
  end

  defp do_strip_locale_from_helper(%{helper: helper} = route, locale) do
    helper = Localize.Routes.LocalizedHelpers.strip_locale(helper, locale)
    %{route | helper: helper}
  end

  defp locale_from_args(%{private: %{localize_locale: locale}}) do
    locale
  end

  defp locale_from_args(_other) do
    nil
  end

  @doc false
  def strip_locale(route) do
    Localize.Routes.LocalizedHelpers.strip_locale(route)
  end

  defp escape_interpolation(path) do
    Macro.prewalk(path, fn
      {{:., _, [Kernel, :to_string]}, _, [{:locale, _, _}]} ->
        ~S"#{locale}"

      {{:., _, [Kernel, :to_string]}, _, [{:language, _, _}]} ->
        ~S"#{language}"

      {{:., _, [Kernel, :to_string]}, _, [{:territory, _, _}]} ->
        ~S"#{territory}"

      other ->
        other
    end)
  end
end
