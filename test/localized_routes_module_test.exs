defmodule LocalizedRoutesModuleTest do
  use ExUnit.Case, async: true

  # The generated `<Router>.LocalizedRoutes` module exists so localized
  # routes can be listed with `mix phx.routes`, as its own moduledoc
  # instructs. It is not a router, so it receives none of
  # `Phoenix.Router`'s callbacks — and `Phoenix.Router.ConsoleFormatter`
  # calls `formatted_routes/1` and `__helpers__/0` on whatever module it
  # is handed. Without them `mix phx.routes MyApp.Router.LocalizedRoutes`
  # raised UndefinedFunctionError.

  @module MyApp.Router.LocalizedRoutes

  describe "the module the console formatter needs" do
    test "exports the callbacks ConsoleFormatter calls" do
      Code.ensure_loaded!(@module)

      assert function_exported?(@module, :__routes__, 0)
      assert function_exported?(@module, :formatted_routes, 1)
      assert function_exported?(@module, :__helpers__, 0)
    end

    test "formatted_routes/1 returns one entry per localized route" do
      formatted = @module.formatted_routes([])

      assert length(formatted) == length(@module.__routes__())
      assert Enum.all?(formatted, &Map.has_key?(&1, :path))
      assert Enum.all?(formatted, &Map.has_key?(&1, :verb))
    end

    test "__helpers__/0 agrees with the router the routes came from" do
      assert @module.__helpers__() == MyApp.Router.__helpers__()
    end
  end

  describe "rendering through Phoenix's console formatter" do
    test "formats without raising, and lists localized paths" do
      output = Phoenix.Router.ConsoleFormatter.format(@module)

      assert is_binary(output)

      # Localized variants of /pages/:page for the configured locales.
      assert output =~ "/pages/:page"
      assert output =~ "/pages_fr/:page"
      assert output =~ "/pages_de/:page"
    end

    test "includes routes carrying an interpolated locale segment" do
      output = Phoenix.Router.ConsoleFormatter.format(@module)

      assert output =~ "/en/locale/pages/:page"
      assert output =~ "/fr/locale/pages_fr/:page"
    end
  end

  describe "option passthrough to Phoenix.VerifiedRoutes" do
    # Only :gettext is consumed by Localize.VerifiedRoutes; everything
    # else must reach Phoenix untouched. :statics is the one that bites —
    # the default Phoenix layouts reference ~p"/images/..." and
    # ~p"/assets/...", which warn unless it is passed.

    defp compile_warnings(source) do
      {_result, diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(source) end)
      Enum.filter(diagnostics, &(&1.severity == :warning))
    end

    test ":statics reaches Phoenix and silences static-asset warnings" do
      warnings =
        compile_warnings(~S|
        defmodule PassthroughWithStatics do
          use Localize.VerifiedRoutes,
            router: MyApp.Router, endpoint: MyApp.Endpoint,
            gettext: MyApp.Gettext, statics: ["images", "assets"]

          def logo, do: ~p"/images/logo.svg"
          def css, do: ~p"/assets/css/app.css"
        end|)

      assert warnings == []
    end

    test "without :statics the asset paths warn, confirming the option is what matters" do
      warnings =
        compile_warnings(~S|
        defmodule PassthroughWithoutStatics do
          use Localize.VerifiedRoutes,
            router: MyApp.Router, endpoint: MyApp.Endpoint, gettext: MyApp.Gettext

          def logo, do: ~p"/images/logo.svg"
        end|)

      assert [warning] = warnings
      assert warning.message =~ "no route path"
      assert warning.message =~ "/images/logo.svg"
    end
  end
end
