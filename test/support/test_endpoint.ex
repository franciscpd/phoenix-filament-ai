defmodule PhoenixFilamentAI.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :phoenix_filament_ai

  plug(Plug.Session,
    store: :cookie,
    key: "_pfa_test_key",
    signing_salt: "test_salt"
  )
end
