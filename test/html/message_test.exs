defmodule Localize.HTML.Message.Test do
  use ExUnit.Case, async: true

  alias Localize.HTML.Message

  defp render(msgid, bindings \\ %{}, options \\ []) do
    msgid
    |> Message.render_to_safe(bindings, options)
    |> Phoenix.HTML.safe_to_string()
  end

  describe "render_to_safe/3 text-only messages" do
    test "static message round-trips unchanged" do
      assert render("Hello, world!") == "Hello, world!"
    end

    test "interpolates bindings" do
      assert render("Hello, {$name}!", %{"name" => "Kip"}) == "Hello, Kip!"
    end

    test "escapes HTML in interpolated bindings" do
      assert render("Hi, {$name}", %{"name" => "<script>"}) ==
               "Hi, &lt;script&gt;"
    end

    test "escapes HTML in literal text" do
      assert render("Hello & welcome") == "Hello &amp; welcome"
    end
  end

  describe "render_to_safe/3 with markup" do
    test "renders bold/strong tags" do
      assert render("Read the {#bold}terms{/bold}") ==
               "Read the <strong>terms</strong>"

      assert render("Read the {#strong}terms{/strong}") ==
               "Read the <strong>terms</strong>"
    end

    test "renders italic/emphasis/em tags" do
      assert render("Be {#italic}careful{/italic}") ==
               "Be <em>careful</em>"

      assert render("Be {#emphasis}careful{/emphasis}") ==
               "Be <em>careful</em>"

      assert render("Be {#em}careful{/em}") ==
               "Be <em>careful</em>"
    end

    test "renders link with escaped href" do
      assert render("Visit {#link href=|/home|}home{/link}") ==
               ~s|Visit <a href="/home">home</a>|
    end

    test "link with navigate attribute emits LiveView navigate link" do
      rendered = render("Go to {#link navigate=|/dashboard|}dashboard{/link}")

      assert rendered =~ ~s|href="/dashboard"|
      assert rendered =~ ~s|data-phx-link="redirect"|
      assert rendered =~ ~s|data-phx-link-state="push"|
    end

    test "link with patch attribute emits LiveView patch link" do
      rendered = render("Filter by {#link patch=|/list?tag=foo|}foo{/link}")

      assert rendered =~ ~s|data-phx-link="patch"|
      assert rendered =~ ~s|data-phx-link-state="push"|
    end

    test "escapes hostile attribute values delivered via bindings" do
      # Attribute values supplied through bindings are HTML-escaped by
      # the link renderer.
      msg = "Visit {#link href=$url}home{/link}"
      hostile = "\" onclick=\"alert(1)"

      rendered = render(msg, %{"url" => hostile})

      assert rendered =~ "&quot;"
      refute rendered =~ "<a href=\"\" onclick=\"alert(1)\">"
    end

    test "renders standalone br" do
      # Phoenix's HEEx engine emits HTML5-style `<br>` (no self-closing
      # slash) for void elements.
      assert render("first{#br/}second") == "first<br>second"
    end

    test "renders nested markup" do
      assert render("{#bold}very {#italic}bold{/italic}{/bold}") ==
               "<strong>very <em>bold</em></strong>"
    end

    test "escapes text inside markup" do
      assert render("{#bold}A & B{/bold}") == "<strong>A &amp; B</strong>"
    end

    test "interpolates bindings inside markup" do
      assert render("{#bold}{$name}{/bold}", %{"name" => "Kip"}) ==
               "<strong>Kip</strong>"
    end
  end

  describe "component registry" do
    test "per-call :components overrides defaults" do
      # Renderers must return either `Phoenix.LiveView.Rendered.t()`
      # (via `~H`) or a `{:safe, iodata}` value. Raw iodata gets escaped.
      custom = %{
        "bold" => fn %{children: c} -> {:safe, ["<b>", elem(c, 1), "</b>"]} end
      }

      assert render("{#bold}x{/bold}", %{}, components: custom) ==
               "<b>x</b>"
    end

    test "per-call :components adds new tags" do
      custom = %{
        "user" => fn %{attrs: a, children: c} ->
          {:safe,
           [
             "<span class=\"user-",
             a |> Map.get("id", "") |> to_string(),
             "\">",
             elem(c, 1),
             "</span>"
           ]}
        end
      }

      assert render("Hello {#user id=42}Kip{/user}", %{}, components: custom) ==
               ~s|Hello <span class="user-42">Kip</span>|
    end
  end

  describe "unknown markup" do
    test "returns a descriptive error" do
      assert {:error, %Message.UnknownMarkupError{} = error} =
               Message.render_to_safe("Hello {#weird}there{/weird}", %{})

      assert Exception.message(error) =~ ~s(unknown MF2 markup tag "weird")
    end
  end

  describe "format errors" do
    test "returns an error for invalid MF2 syntax" do
      assert {:error, %Localize.ParseError{}} = Message.render_to_safe("Hello {unclosed", %{})
    end

    test "returns an error for unbalanced markup" do
      assert {:error, %Localize.FormatError{}} = Message.render_to_safe("{#bold}oops", %{})
    end

    test "returns an error for a msgid, components or options of the wrong type" do
      for msgid <- [nil, 42, %{}, :atom] do
        assert {:error, %Localize.InvalidValueError{}} = Message.render_to_safe(msgid, %{})
      end

      assert {:error, %Localize.InvalidValueError{}} =
               Message.render_to_safe("Hi", %{}, components: [:not_a_map])

      assert {:error, %Localize.InvalidValueError{}} = Message.render_to_safe("Hi", %{}, 42)
    end
  end

  describe "<.message /> component" do
    import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
    import Phoenix.Component

    test "renders msgid with bindings" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Localize.HTML.Message.message msgid="Hello {$name}!" bindings={%{"name" => "Kip"}} />
        """)

      assert html == "Hello Kip!"
    end

    test "renders markup" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Localize.HTML.Message.message msgid="Read the {#bold}terms{/bold}" />
        """)

      assert html == "Read the <strong>terms</strong>"
    end

    @tag :capture_log
    test "renders the children of an unknown markup tag" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Localize.HTML.Message.message msgid="Hello {#weird}there{/weird}" />
        """)

      assert html == "Hello there"
    end

    test "logs an unknown markup tag" do
      assigns = %{}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          rendered_to_string(~H"""
          <Localize.HTML.Message.message msgid="Hello {#weird}there{/weird}" />
          """)
        end)

      assert log =~ ~s(unknown MF2 markup tag "weird")
    end

    @tag :capture_log
    test "renders the escaped source of a message that cannot be formatted" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Localize.HTML.Message.message msgid="<b>Hello {unclosed" />
        """)

      assert html == "&lt;b&gt;Hello {unclosed"
    end

    test "facade Localize.HTML.message/1 works as a component" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <Localize.HTML.message msgid="Hello, {$name}" bindings={%{"name" => "Kip"}} />
        """)

      assert html == "Hello, Kip"
    end
  end
end
