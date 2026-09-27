import Config

config :logger, level: :warning

config :localize_web, MyApp.Endpoint, secret_key_base: "kjoy3o1zeidquwy1398juxzldjlksahdk3"

config :localize_web, MyApp.LiveEndpoint,
  secret_key_base: String.duplicate("kjoy3o1zeidquwy1398juxzldjlksahdk3", 2),
  live_view: [signing_salt: "localize_live"]
