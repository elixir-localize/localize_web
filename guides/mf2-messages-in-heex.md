# MF2 Messages in HEEx

This guide covers writing ICU MessageFormat 2 (MF2) messages in Phoenix templates. Three tools are available, in increasing order of HEEx-specificity:

* `~t` sigil from `Localize.Message.Sigils` — compile-time MF2 translation that returns a `String.t()`. Best when you only need plain text (no markup). Usable anywhere in Elixir code, not just templates.

* `Localize.HTML.t/1` macro — the **recommended** form for HEEx templates. Combines Gettext extraction, MF2 interpolation, and markup rendering in one call: `{t("...")}`. Supports inline markup such as `{#bold}…{/bold}` or `{#link navigate=…}…{/link}`.

* `Localize.HTML.message/1` function component — for cases where the MF2 source is dynamic (loaded from a database, etc.). Accepts a runtime `:msgid` attribute and `:bindings` map.

All three rely on a Gettext backend configured with `Localize.Gettext.Interpolation`.

## Setup

### 1. Configure a Gettext backend with MF2 interpolation

```elixir
defmodule MyApp.Gettext do
  use Gettext.Backend,
    otp_app: :my_app,
    interpolation: Localize.Gettext.Interpolation
end
```

Without `Localize.Gettext.Interpolation`, MF2 placeholders like `{$name}` are returned literally because Gettext's default interpolation only recognises the `%{name}` form.

### 2. Opt the calling module into `~t` and `t/1`

In a Phoenix app, the most common spot is the HTML helpers macro in `MyAppWeb`:

```elixir
defmodule MyAppWeb do
  def html_helpers do
    quote do
      use Phoenix.Component
      import Localize.HTML
      use Localize.Message.Sigils,
        backend: MyApp.Gettext,
        sigils: [domain: "messages"]
    end
  end
end
```

Every LiveView, component, and HTML module that does `use MyAppWeb, :html` now has `~t`, the `t/1` macro, and `<.message>` available.

`use Localize.Message.Sigils` accepts:

* `:backend` — the Gettext backend module. Required.

* `:sigils` — a keyword list of sigil-level defaults:

    * `:domain` — default Gettext domain. The default is `:default`.

    * `:context` — default Gettext message context. The default is `nil`.

## The `~t` sigil — plain-text translation

`~t"…"` rewrites Elixir `#{expr}` interpolations as MF2 `{$name}` placeholders, canonicalises the resulting message, registers it with Gettext for translation lookup, and evaluates the MF2 message at runtime.

```elixir
def render(assigns) do
  ~H"""
  <h1>{~t"Hello, #{@user.name}!"}</h1>
  <p>{~t"You have #{count = length(@items)} item(s)"}</p>
  """
end
```

At compile time, `~t"Hello, #{@user.name}!"` expands to roughly:

```elixir
Gettext.Macros.dpgettext_with_backend(
  MyApp.Gettext,
  "messages",
  nil,
  "Hello, {$user_name}!",
  %{user_name: @user.name}
)
```

The `.po` msgid is the MF2-canonical form with `{$name}` placeholders, so translators can use MF2 features (selectors, formatters, plural categories) per-locale without changing the source code.

### Binding key derivation

Binding names are derived from the interpolated expression:

| Source                  | Derived key       |
| ----------------------- | ----------------- |
| `#{name}`               | `name`            |
| `#{@count}`             | `count`           |
| `#{user.name}`          | `user_name`       |
| `#{String.upcase(x)}`   | `string_upcase`   |
| `#{total = a + b}`      | `total`           |

The explicit `key = expr` form always wins and is the way to disambiguate when two expressions would derive the same key (the macro raises a compile error if you don't):

```elixir
~t"#{a = String.upcase(first)} vs #{b = String.upcase(second)}"
```

Identical expressions interpolated twice share a single binding:

```elixir
~t"#{name} is #{name}"
# => msgid "{$name} is {$name}"
```

### Translator workflow

Run the standard Gettext extraction tasks:

```bash
mix gettext.extract
mix gettext.merge priv/gettext
```

The extracted msgids are valid MF2. A translator localising `"Hello, {$user_name}!"` into French may simply translate the text:

```pot
msgid "Hello, {$user_name}!"
msgstr "Bonjour, {$user_name} !"
```

…or use MF2 features when the target language needs them, for example pluralisation:

```pot
msgid "You have {$count} item(s)"
msgstr ".input {$count :number}\n.match $count\n0 {{Aucun élément}}\n1 {{Un élément}}\n* {{{$count} éléments}}"
```

The MF2 evaluator runs the translated string with the bindings supplied at the call site, so pluralisation rules can change per locale without code changes.

## The `t/1` macro — translations with markup (recommended)

The `Localize.HTML.t/1` macro is the most ergonomic way to write translations in HEEx. It combines compile-time Gettext extraction, MF2 interpolation, and markup rendering in one call:

```heex
<h1>{t("Hello, #{@user.name}!")}</h1>
<p>{t("By signing up you accept our {#link navigate=|/terms|}terms{/link}.")}</p>
<p>{t("Read {#bold}#{@count} item(s){/bold}")}</p>
```

At compile time, the macro:

1. Walks Elixir `#{expr}` interpolations and derives flat MF2 binding names (same rules as `~t`).
2. Rewrites the message as canonical MF2 source with `{$name}` placeholders.
3. Emits a `Gettext.Macros.dpgettext_with_backend/5` call so `mix gettext.extract` picks up the msgid.

At runtime:

1. The Gettext lookup returns the translated MF2 source **without** stripping markup (via an internal sentinel that bypasses the markup-stripping interpolation path).
2. The translated source is walked via `Localize.Message.format_to_safe_list/3`.
3. Each markup node is dispatched to a registered component (defaults documented under `<.message>` below).

### Differences from `~t`

| Feature                 | `~t`              | `t/1`                              |
| ----------------------- | ----------------- | ---------------------------------- |
| Returns                 | `String.t()`      | `Phoenix.HTML.safe()`              |
| Use site                | Anywhere          | HEEx `{...}` interpolation         |
| MF2 markup              | Stripped          | Rendered as HEEx via the registry  |
| Bindings from `@assign` | Yes (compile-time AST walk) | Yes (HEEx rewrites `@x` to `assigns.x` before the macro sees it, and the `assigns` prefix is stripped from the derived binding name) |

Use `~t` when you need a plain string outside of HEEx, e.g. for error messages, page titles assigned to other variables, etc. Use `t/1` everywhere else inside templates.

### Options

`t/2` accepts a keyword-list second argument:

```heex
{t("Hello, #{@name}!", locale: :fr)}
{t("Click {#link navigate=|/x|}here{/link}", components: %{"link" => &my_link/1})}
```

* `:locale` overrides `Localize.get_locale/0` for this render only.

* `:components` is a per-call markup component override (same shape as `<.message>`'s).

## The `<.message>` component — for dynamic msgids

MF2 supports inline markup tags. Examples:

```
Please {#bold}read{/bold} the {#link href=|/terms|}terms{/terms}.
Line one{#br/}line two.
```

`Localize.Message.format/3` strips these tags. `<Localize.HTML.message />` preserves them by walking `Localize.Message.format_to_safe_list/3` and dispatching each markup node to a renderer.

```heex
<Localize.HTML.message
  msgid={~t"Read the #{document = "terms"} before clicking {#bold}Accept{/bold}"}
/>
```

Or with attributes directly:

```heex
<Localize.HTML.message
  msgid="Visit {#link href=|/home|}home{/link}"
/>
```

### Attributes

* `:msgid` — the MF2 message string. Required.

* `:bindings` — a map of variable bindings for MF2 placeholders. The default is `%{}`. When `:msgid` comes from `~t`, leave this empty — `~t` injects the bindings into the gettext call.

* `:locale` — a locale name or language tag. The default is `Localize.get_locale/0`.

* `:components` — a map of `%{markup_name => renderer_fun}` overriding defaults and app config for this render only. The default is `%{}`.

### Default markup renderers

| MF2 tag           | HEEx output         |
| ----------------- | ------------------- |
| `bold`, `strong`  | `<strong>…</strong>` |
| `italic`, `emphasis`, `em` | `<em>…</em>` |
| `code`            | `<code>…</code>`    |
| `link`            | Phoenix `<.link>` — accepts `href`, `navigate`, or `patch` MF2 attributes |
| `br` (standalone) | `<br>`              |

All literal text and binding values are HTML-escaped automatically.

The `link` renderer uses Phoenix.Component's `<.link>`, so translators can
emit same-app navigation by writing `navigate` or `patch` in the MF2 source:

```
{#link navigate=|/dashboard|}dashboard{/link}
{#link patch=|/list?tag=urgent|}urgent items{/link}
{#link href=|https://example.com|}external{/link}
```

The renderer falls back to `href="#"` when none of the three attributes
is present. `<.link>` also rejects unsafe `javascript:` and `data:`
destinations at runtime.

### Adding custom markup tags

Markup-name lookups consult three sources in order:

1. The component's `:components` attribute (per-call override).

2. `config :localize_web, :mf2_markup, components: %{…}` (app-wide).

3. Built-in defaults from `Localize.HTML.Message.default_components/0`.

A renderer is a function of one argument `%{attrs: map, children: safe}` that returns either a `Phoenix.LiveView.Rendered.t()` (the recommended form, produced by `~H`) or a `Phoenix.HTML.safe()` value (`{:safe, iodata}`). The `children` value is already rendered and HTML-escaped — pass it straight through, wrap it, or ignore it, but do not escape it again.

Recommended form, using `~H`:

```elixir
defmodule MyAppWeb.MF2 do
  use Phoenix.Component

  def user(%{attrs: %{"id" => id}, children: children}) do
    assigns = %{id: id, children: children}

    ~H"""
    <span class={"user-#{@id}"}>{@children}</span>
    """
  end
end

config :localize_web, :mf2_markup,
  components: %{"user" => &MyAppWeb.MF2.user/1}
```

Raw form, using `{:safe, iodata}`:

```elixir
fn %{attrs: %{"id" => id}, children: {:safe, child_iodata}} ->
  {:safe,
   [~s(<span class="user-), to_string(id), ~s(">), child_iodata, "</span>"]}
end
```

To start from the defaults and add your own:

```elixir
config :localize_web, :mf2_markup,
  components: Map.merge(
    Localize.HTML.Message.default_components(),
    %{"user" => &MyAppWeb.MF2.user/1}
  )
```

### Unknown tags raise

If a translator writes `{#weird}…{/weird}` and `weird` isn't registered, the component raises `Localize.HTML.Message.UnknownMarkupError` listing the tag and the registered tag names. This is intentional — silent fallbacks hide translator mistakes.

## Choosing between `~t`, `t/1`, and `<.message>`

* **Inside HEEx templates** → use `t/1`. It handles both plain text and inline markup, extracts to `.po`, and renders markup correctly.

* **Outside HEEx** (error messages, dynamic strings, anywhere that needs a `String.t()`) → use `~t`. Note that markup is stripped — `~t` is text-only.

* **MF2 source loaded at runtime** (from a database, user content, etc.) → use `<.message msgid={...} bindings={...} />`. Bypasses Gettext extraction (the msgid isn't a literal) but supports the same markup-rendering pipeline.

## A complete example

```elixir
defmodule MyAppWeb.TermsLive do
  use MyAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <header>
      <h1>{t("Welcome, #{@user.name}")}</h1>
    </header>

    <section>
      <p>{t("By signing up you accept our {#link navigate=|/terms|}terms{/link} and {#link navigate=|/privacy|}privacy policy{/link}.")}</p>
    </section>

    <p>{t("You have #{count = @notification_count} new notification(s)")}</p>
    """
  end
end
```

After `mix gettext.extract`, the `.pot` file contains:

```pot
msgid "Welcome, {$user_name}"
msgstr ""

msgid "By signing up you accept our {#link href=|/terms|}terms{/link} and {#link href=|/privacy|}privacy policy{/link}."
msgstr ""

msgid "You have {$count} new notification(s)"
msgstr ""
```

The third msgid is a natural fit for MF2 selectors in the translation — number-aware pluralisation is the translator's job, not the developer's.
