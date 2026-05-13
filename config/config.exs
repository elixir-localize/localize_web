import Config

config :phoenix, :json_library, Jason

# Locales referenced by the test suite (display-name lookups, route
# translation, plug routing, MF2 rendering). The `mix test` alias in
# `mix.exs` invokes `mix localize.download_locales`, which populates
# the runtime cache from this list on a fresh checkout / in CI.
# `localize.download_locales` reads compile-time config and runs in
# the default Mix env, so the list lives here rather than in test.exs.
config :localize,
  supported_locales: ~w(en fr de th ja ar zh zh-Hans zh-Hant)

import_config "#{Mix.env()}.exs"
