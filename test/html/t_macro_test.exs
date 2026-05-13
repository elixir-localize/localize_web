defmodule Localize.HTML.TMacroTest do
  use ExUnit.Case, async: true

  # Module that opts into Localize.Message.Sigils + imports Localize.HTML so
  # the `t/1` macro is in scope. Tests below render the macro's output
  # to a string and assert.
  defmodule Fixture do
    use Phoenix.Component
    use Localize.Message.Sigils, backend: Localize.Gettext
    import Localize.HTML

    def static(assigns) do
      ~H"""
      <p>{t("Hello, world!")}</p>
      """
    end

    def with_var(assigns) do
      ~H"""
      <p>{t("Hello, #{@name}!")}</p>
      """
    end

    def with_dot_access(assigns) do
      ~H"""
      <p>{t("Hello, #{@user.name}!")}</p>
      """
    end

    def with_markup(assigns) do
      ~H"""
      <p>{t("Read the {#bold}terms{/bold}")}</p>
      """
    end

    def with_markup_and_binding(assigns) do
      ~H"""
      <p>{t("Read {#bold}#{@count} item(s){/bold}")}</p>
      """
    end

    def with_link(assigns) do
      ~H"""
      <p>{t("Visit {#link href=|/home|}home{/link}")}</p>
      """
    end

    def with_navigate_link(assigns) do
      ~H"""
      <p>{t("Go to {#link navigate=|/dashboard|}dashboard{/link}")}</p>
      """
    end

    def escapes_bindings(assigns) do
      ~H"""
      <p>{t("Hi, #{@input}")}</p>
      """
    end
  end

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  test "static message renders without bindings" do
    assert rendered_to_string(Fixture.static(%{})) == "<p>Hello, world!</p>"
  end

  test "interpolated variable becomes a flat MF2 binding" do
    assert rendered_to_string(Fixture.with_var(%{name: "Kip"})) ==
             "<p>Hello, Kip!</p>"
  end

  test "dot access in interpolation derives parent_key binding" do
    assert rendered_to_string(Fixture.with_dot_access(%{user: %{name: "Kip"}})) ==
             "<p>Hello, Kip!</p>"
  end

  test "MF2 markup is rendered via the component registry (not stripped)" do
    assert rendered_to_string(Fixture.with_markup(%{})) ==
             "<p>Read the <strong>terms</strong></p>"
  end

  test "markup + binding interpolation work together" do
    assert rendered_to_string(Fixture.with_markup_and_binding(%{count: 3})) ==
             "<p>Read <strong>3 item(s)</strong></p>"
  end

  test "MF2 link markup emits Phoenix <.link> with href" do
    rendered = rendered_to_string(Fixture.with_link(%{}))
    assert rendered =~ ~s|<a href="/home">home</a>|
  end

  test "MF2 link markup with navigate emits LiveView navigate link" do
    rendered = rendered_to_string(Fixture.with_navigate_link(%{}))
    assert rendered =~ ~s|data-phx-link="redirect"|
    assert rendered =~ ~s|href="/dashboard"|
  end

  test "binding values are HTML-escaped" do
    assert rendered_to_string(Fixture.escapes_bindings(%{input: "<script>"})) ==
             "<p>Hi, &lt;script&gt;</p>"
  end

  describe "compile-time errors" do
    test "missing `use Localize.Message.Sigils` raises" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule NoSigilsUse do
            import Localize.HTML
            def go, do: t("hello")
          end
          """)
        end

      assert Exception.message(error) =~ "without `use Localize.Message.Sigils"
    end

    test "invalid MF2 raises at compile time" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule BadMF2 do
            use Localize.Message.Sigils, backend: Localize.Gettext
            import Localize.HTML
            def go, do: t("Hello {unclosed")
          end
          """)
        end

      assert Exception.message(error) =~ "Localize.HTML.t/1"
    end

    test "non-literal msgid raises" do
      error =
        assert_raise CompileError, fn ->
          Code.eval_string("""
          defmodule DynamicMsgid do
            use Localize.Message.Sigils, backend: Localize.Gettext
            import Localize.HTML
            def go(x), do: t(x)
          end
          """)
        end

      assert Exception.message(error) =~ "requires a string literal"
    end
  end
end
