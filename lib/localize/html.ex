defmodule Localize.HTML do
  @moduledoc """
  Facade module providing HTML form select helpers for localized data.

  This module delegates to specialized submodules that generate `<select>` tags and option lists for currencies, territories, locales, units of measure, and months. Each helper localizes display names according to the current or specified locale using the [Localize](https://hex.pm/packages/localize) library.

  ## Delegate Functions

  * `currency_select/3` and `currency_options/1` — see `Localize.HTML.Currency`.

  * `territory_select/3` and `territory_options/1` — see `Localize.HTML.Territory`.

  * `locale_select/3` and `locale_options/1` — see `Localize.HTML.Locale`.

  * `unit_select/3` and `unit_options/1` — see `Localize.HTML.Unit`.

  * `month_select/3` and `month_options/1` — see `Localize.HTML.Month`.

  * `message/1` — renders an MF2 message with inline markup, see `Localize.HTML.Message`.

  * `t/1`, `t/2` — compile-time MF2 translation macro for HEEx templates.
    Combines Gettext lookup with MF2 interpolation and markup rendering
    in one call: `{t("Hello, \#{@user.name}!")}`.

  """

  if Code.ensure_loaded?(Phoenix.Component) do
    defdelegate message(assigns), to: Localize.HTML.Message
  end

  @doc """
  Translates an MF2 message at compile time and renders it (including
  inline markup) at runtime.

  This is the macro-form equivalent of `~t` + `<.message>` combined.
  Suitable for use directly inside HEEx body interpolation:

      <h1>{t("Hello, \#{@user.name}!")}</h1>
      <p>{t("By signing up you accept our {#link navigate=|/terms|}terms{/link}.")}</p>

  Elixir-style `\#{expr}` interpolations are rewritten as MF2 `{$name}`
  placeholders at compile time using the same key-derivation rules as
  the `~t` sigil (see `Localize.Message.Sigils`). The canonical msgid
  is registered with Gettext for translation extraction; at runtime the
  translated message is walked via
  `Localize.Message.format_to_safe_list/3` so MF2 markup tags such as
  `{#bold}…{/bold}` and `{#link href=…}…{/link}` are dispatched to the
  Phoenix function components registered with `Localize.HTML.Message`.

  The calling module must opt in with:

      use Localize.Message.Sigils, backend: MyApp.Gettext

  ### Arguments

  * `msgid` is an MF2 message string literal. May contain Elixir
    `\#{expr}` interpolations.

  * `options` is a keyword list of options (only `t/2`).

  ### Options

  * `:locale` overrides the current locale for this render only.
    The default is `Localize.get_locale/0`.

  * `:components` is a map of `%{markup_name => renderer_fun}` that
    overrides the default markup component registry for this render
    only. The default is `%{}`.

  ### Returns

  * A `Phoenix.HTML.safe()` value suitable for HEEx interpolation.

  ### Examples

      {t("Hello, world!")}
      {t("Hello, \#{name}!")}
      {t("Read {#bold}\#{count} item(s){/bold}")}
      {t("Click {#link patch=|/x|}here{/link}", locale: :fr)}

  """
  defmacro t(msgid), do: build_t_ast(msgid, [], __CALLER__)
  defmacro t(msgid, options), do: build_t_ast(msgid, options, __CALLER__)

  defp build_t_ast(msgid_ast, options_ast, caller) do
    config = Localize.Message.Sigils.fetch_config!(caller, [])
    meta = []

    pieces =
      case msgid_ast do
        binary when is_binary(binary) ->
          [binary]

        {:<<>>, _meta, pieces} ->
          pieces

        other ->
          raise CompileError,
            file: caller.file,
            line: caller.line,
            description:
              "Localize.HTML.t/1 requires a string literal msgid, got: #{Macro.to_string(other)}"
      end

    {msgid, bindings} = Localize.Message.Sigils.extract_interpolations!(pieces, caller, meta)

    canonical =
      Localize.Message.Sigils.compile_time_parse_or_raise!(
        msgid,
        [pretty: false],
        caller,
        meta,
        "Localize.HTML.t/1"
      )

    %{backend: backend, domain: domain, context: context} = config
    bindings_map_ast = {:%{}, [], bindings}

    quote do
      translated =
        Gettext.Macros.dpgettext_with_backend(
          unquote(backend),
          unquote(domain),
          unquote(context),
          unquote(canonical),
          Localize.Gettext.Interpolation.skip_interpolation_sentinel()
        )

      Localize.HTML.Message.render_to_safe(
        translated,
        unquote(bindings_map_ast),
        unquote(options_ast)
      )
    end
  end

  defdelegate currency_select(form, field, options), to: Localize.HTML.Currency, as: :select
  defdelegate currency_options(options), to: Localize.HTML.Currency, as: :currency_options

  defdelegate unit_select(form, field, options), to: Localize.HTML.Unit, as: :select
  defdelegate unit_options(options), to: Localize.HTML.Unit, as: :unit_options

  defdelegate territory_select(form, field, options), to: Localize.HTML.Territory, as: :select
  defdelegate territory_options(options), to: Localize.HTML.Territory, as: :territory_options

  defdelegate locale_select(form, field, options), to: Localize.HTML.Locale, as: :select
  defdelegate locale_options(options), to: Localize.HTML.Locale, as: :locale_options

  defdelegate month_select(form, field, options), to: Localize.HTML.Month, as: :select
  defdelegate month_options(options), to: Localize.HTML.Month, as: :month_options
end
