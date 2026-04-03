defmodule SimplePlugRouter do
  @moduledoc false

  use Plug.Router

  plug(:match)
  plug(Localize.Plug.PutLocale, from: :path)
  plug(:dispatch)

  get "/thing/:locale" do
    send_resp(conn, 200, "")
  end

  get "/thing/:locale/other" do
    send_resp(conn, 200, "")
  end
end
