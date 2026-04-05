Application.put_env(:phoenix_filament_ai, PhoenixFilamentAI.TestEndpoint,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test_salt"]
)

ExUnit.start(exclude: [:integration])
