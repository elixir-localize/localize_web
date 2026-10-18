defmodule MyApp.Gettext do
  use Gettext.Backend,
    otp_app: :localize_web,
    interpolation: Localize.Gettext.Interpolation
end
