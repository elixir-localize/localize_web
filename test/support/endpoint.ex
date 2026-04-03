defmodule MyApp.Endpoint do
  use Phoenix.Endpoint, otp_app: :localize_web

  plug(MyApp.Router)
end
