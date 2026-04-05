defmodule PhoenixFilamentAI.Config do
  @moduledoc """
  NimbleOptions-based configuration validation for PhoenixFilamentAI.

  ## Required Options

  - `:store` — the store module (atom) implementing `PhoenixAI.Store` behaviour
  - `:provider` — the AI provider (atom), e.g. `:openai`, `:anthropic`
  - `:model` — the model identifier (string), e.g. `"gpt-4o"`

  ## Optional Options

  See `schema/0` for all available options and their defaults.

  ## Examples

      PhoenixFilamentAI.Config.validate!(
        store: MyApp.AIStore,
        provider: :openai,
        model: "gpt-4o"
      )

  """

  @chat_widget_schema [
    column_span: [type: :pos_integer, default: 6, doc: "Grid column span for the widget."],
    sort: [type: :non_neg_integer, default: 100, doc: "Sort order on the dashboard."],
    system_prompt: [
      type: :string,
      default: "You are a helpful AI assistant.",
      doc: "System prompt for the chat widget."
    ],
    max_tokens: [type: :pos_integer, default: 4096, doc: "Maximum tokens for responses."],
    title: [type: :string, default: "AI Assistant", doc: "Widget title."]
  ]

  @chat_schema [
    system_prompt: [type: :string, doc: "Default system prompt for chat sessions."],
    max_tokens: [type: :pos_integer, doc: "Maximum tokens for chat responses."],
    temperature: [type: :float, doc: "Temperature for chat responses."]
  ]

  @schema [
    store: [type: :atom, required: true, doc: "Store module implementing PhoenixAI.Store."],
    provider: [type: :atom, required: true, doc: "AI provider atom (e.g. :openai, :anthropic)."],
    model: [type: :string, required: true, doc: "Model identifier (e.g. \"gpt-4o\")."],
    chat_widget: [
      type: {:or, [:boolean, keyword_list: @chat_widget_schema]},
      default: true,
      doc: "Enable chat widget on dashboard. Pass `true`, `false`, or a keyword list of options."
    ],
    chat_page: [type: :boolean, default: true, doc: "Enable standalone chat page."],
    conversations: [type: :boolean, default: false, doc: "Enable conversation history."],
    cost_dashboard: [type: :boolean, default: false, doc: "Enable cost tracking dashboard."],
    event_log: [type: :boolean, default: false, doc: "Enable AI event log."],
    nav_group: [type: :string, default: "AI", doc: "Navigation group label."],
    nav_icon: [type: :string, default: "hero-sparkles", doc: "Navigation icon name."],
    ets_warning: [
      type: :boolean,
      default: true,
      doc: "Show warning when using ETS-based store in production."
    ],
    api_key: [type: :string, doc: "Optional API key override."],
    chat: [
      type: :keyword_list,
      keys: @chat_schema,
      default: [],
      doc: "Chat-specific options."
    ]
  ]

  @doc "Returns the NimbleOptions schema definition."
  def schema, do: @schema

  @doc """
  Validates the given options against the config schema.

  Returns `{:ok, validated_opts}` or `{:error, %NimbleOptions.ValidationError{}}`.
  """
  @spec validate(keyword()) :: {:ok, keyword()} | {:error, NimbleOptions.ValidationError.t()}
  def validate(opts) do
    NimbleOptions.validate(opts, @schema)
  end

  @doc """
  Validates the given options, raising on failure.

  Returns the validated keyword list on success.
  """
  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    NimbleOptions.validate!(opts, @schema)
  end

  @doc """
  Checks whether a feature toggle is enabled in the validated config.

  For `:chat_widget`, both `true` and a keyword list count as enabled.
  """
  @spec feature_enabled?(keyword(), atom()) :: boolean()
  def feature_enabled?(config, feature) do
    case Keyword.get(config, feature) do
      nil -> false
      false -> false
      true -> true
      value when is_list(value) -> true
      _ -> false
    end
  end
end
