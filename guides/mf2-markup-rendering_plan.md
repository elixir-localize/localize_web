# Planned MF2 Markup Rendering for HEEX

## Context

MF2 messages can contain markup elements like `{#link href=|/home|}here{/link}`, `{#bold}...{/bold}`, or standalone `{#br/}`. Translators embed these in message strings so that layout and styling can be applied at render time without freezing HTML into the translation.

As of `localize` v0.8.0 the core package provides `Localize.Message.format_to_safe_list/3`, which returns a nested list of `{:text, String.t()}` and `{:markup, name, options, children}` tuples. The core package is deliberately Phoenix-free; this package (`localize_web`) is where the Phoenix-specific rendering glue belongs.

This plan describes the Phoenix LiveView / HEEX integration layer, to be implemented in `localize_web` as a follow-up to the core API.

## Goal

Let users write templates like:

```heex
<.localized message={gettext("Welcome! Visit {#link href=|/about|}our about page{/link} to learn more.")} />
```

…and have the markup render as real `<.link>` elements while variable interpolation, plural selection, and locale resolution continue to work as normal MF2.

## Approach

### New module: `Localize.HTML.Message`

Path: `lib/localize/html/message.ex` — alongside the existing `Localize.HTML.Currency` and `Localize.HTML.Territory`.

Provides:

**1. A function component `localized/1`**

```elixir
defmodule Localize.HTML.Message do
  use Phoenix.Component

  attr :message, :string, required: true
  attr :bindings, :map, default: %{}
  attr :locale, :any, default: nil
  attr :handlers, :map, default: %{},
    doc: "Map of markup name to function(options, children) -> rendered content. Merged with built-in handlers."

  def localized(assigns) do
    nodes = render_nodes(assigns.message, assigns.bindings, assigns.locale, assigns.handlers)
    assigns = assign(assigns, :nodes, nodes)

    ~H"""
    <%= for node <- @nodes do %><%= node %><% end %>
    """
  end
end
```

**2. Default handlers for common markup names**

- `"link"` with `href` option → `<.link href={...}>...</.link>` (Phoenix route-aware; supports verified routes when the handler receives a `~p` sigil input)
- `"bold"` or `"strong"` → `<strong>...</strong>`
- `"italic"` or `"em"` → `<em>...</em>`
- `"br"` (standalone) → `<br>`
- Unknown markup name → wraps children in `<span data-mf2-markup={name}>...</span>` so CSS/JS can still hook in without the component crashing

**3. User-supplied handler override**

Users can pass their own `:handlers` map that takes precedence over the defaults. Each handler is `(options :: map(), children :: iodata()) -> Phoenix.LiveView.Rendered.t() | iodata()`.

## Public API shape

```elixir
import Localize.HTML.Message

# Simplest form — uses default handlers
<.localized message="Click {#link href=|/home|}here{/link}" />

# With variable bindings
<.localized
  message={gettext("Hello {$name}, you have {$count :number} messages")}
  bindings={%{"name" => @user.name, "count" => @unread_count}}
/>

# With custom handler
<.localized
  message={gettext("See {#doc id=|welcome|}the welcome guide{/doc}")}
  handlers={%{"doc" => &MyApp.Docs.link_component/2}}
/>
```

## Verified routes integration

A natural extension: integrate with `Localize.VerifiedRoutes` so that `href` values in markup can be verified at compile time when the template is known. This may require a sigil-based variant, e.g.:

```heex
<.localized_q message={gettext("Click {#link path=|welcome|}here{/link}")} />
```

where `path=|welcome|` is resolved against the app's verified route scope. This is speculative — prove out the plain string form first.

## Error handling

- **Unbalanced markup** (`format_to_safe_list/3` returns `{:error, %FormatError{}}`) → render the raw message string as a fallback and log a warning.
- **Unbound variables** (`format_to_safe_list/3` returns `{:error, %BindError{}}`) → same fallback. This matches Gettext's own behaviour when a binding is missing.
- **Parse error** → raise at compile time if the message is a compile-time literal; log and fall back if dynamic.

## Files to create in `localize_web`

| File | Action |
|---|---|
| `lib/localize/html/message.ex` | **Create** — `Localize.HTML.Message` component with `localized/1` and default handlers |
| `lib/localize/html/message/handlers.ex` | **Create** — default handler implementations, kept small and overridable |
| `test/localize/html/message_test.exs` | **Create** — component rendering tests using `Phoenix.LiveViewTest` helpers |
| `guides/mf2-markup-rendering.md` | Update this file into an end-user guide once implemented |
| `CHANGELOG.md` | Entry under Added |
| `lib/localize/html.ex` (facade) | Add documentation entry pointing to the new module |

## Dependencies

`localize_web` already depends on `localize`, `phoenix`, `phoenix_live_view`, and `phoenix_html`.

## Verification

- `mix compile --warnings-as-errors`
- `mix test` — component renders correctly for text-only, markup-only, mixed, nested, plural+markup, and error cases.
- Manually: spin up a throwaway LiveView app, render a message with `{#link}` markup, confirm the rendered HTML matches expectations and the link is clickable with the correct href.
- `MIX_ENV=release mix docs`

## Open questions

- **Should handlers receive the `assigns` context?** Likely yes — a `link` handler may need access to `@conn` or `@socket` for route generation. Pass it as a third argument: `handler.(options, children, assigns)`.
- **What HTML-escape posture?** `format_to_safe_list/3` returns raw strings — text nodes go straight into HEEX which escapes automatically. Handlers returning iodata should also go through HEEX's escaping. Verify with an XSS-style test case (a binding containing `<script>`).
- **Should we ship an `~L` sigil?** Probably not — the component form is idiomatic and plays nicely with `gettext`.
