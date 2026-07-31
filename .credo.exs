# Credo configuration for Localize.Web.
#
# Mirrors the Localize policy: strict, with `Design.AliasUsage`
# disabled. Web code fully qualifies many calls because module names
# such as `Localize.LanguageTag` read more clearly at the call site than
# an alias, and because trailing segments such as `List` and `String`
# shadow the standard library when aliased. Alias submodules
# opportunistically where the trailing segment does not clash, never as
# a bulk conversion.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/"]
      },
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ],
        extra: [
          # Test support modules are scaffolding — controllers, a Gettext
          # backend, an endpoint — and do not need moduledocs.
          {Credo.Check.Readability.ModuleDoc, files: %{excluded: ["test/"]}},

          # `localized_helpers.ex` generates the route helper functions.
          # Its nesting is the shape of the quoted code it builds rather
          # than of any function a reader follows, and
          # `raise_route_error/9` carries the whole call context so that
          # a helper mismatch can report which locale, action and route
          # were involved. Both are measured against the generated
          # surface rather than hand-written logic.
          {Credo.Check.Refactor.Nesting,
           files: %{excluded: ["lib/localize/routes/localized_helpers.ex"]}},
          {Credo.Check.Refactor.FunctionArity,
           files: %{excluded: ["lib/localize/routes/localized_helpers.ex"]}}
        ]
      }
    }
  ]
}
