defmodule PhoenixFilamentAI.Fixtures do
  def valid_plugin_opts(overrides \\ []) do
    Keyword.merge([store: :test_store, provider: :openai, model: "gpt-4o"], overrides)
  end

  def conversation_attrs(overrides \\ %{}) do
    Map.merge(%{title: "Test Conversation", tags: ["test"], status: :active}, overrides)
  end

  def message_attrs(role \\ :user, overrides \\ %{}) do
    Map.merge(%{role: role, content: "Hello, this is a test message."}, overrides)
  end
end
