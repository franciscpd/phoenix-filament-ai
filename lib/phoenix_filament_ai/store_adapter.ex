defmodule PhoenixFilamentAI.StoreAdapter do
  @moduledoc """
  Single abstraction layer between the plugin and `PhoenixAI.Store`.

  This is the **only** module that knows the Store's function names and
  argument shapes. Every other module in the plugin talks to the store
  exclusively through this adapter, making it trivial to absorb upstream
  API changes in one place.

  ## Design

  - All functions receive `store` (a named store atom, e.g. `:my_store`)
    as the first argument.
  - Return `{:ok, result}` / `{:error, reason}` — no exceptions.
  - Uses **only** the `PhoenixAI.Store` public API — backend-agnostic.
  - No caching — the Store is the single source of truth.
  """

  alias PhoenixAI.Store
  alias PhoenixAI.Store.{Conversation, Message}

  # -------------------------------------------------------------------
  # Conversations
  # -------------------------------------------------------------------

  @doc """
  Lists conversations matching the given filters.

  ## Filters

  Common filters supported by the store adapters:
  - `:user_id` — filter by user
  - `:exclude_deleted` — exclude soft-deleted conversations

  Returns `{:ok, conversations}` or `{:error, reason}`.
  """
  @spec list_conversations(atom(), keyword()) :: {:ok, [Conversation.t()]} | {:error, term()}
  def list_conversations(store, filters \\ []) do
    Store.list_conversations(filters, store: store)
  end

  @doc """
  Gets a conversation by ID, including its messages.

  Returns `{:ok, conversation}` or `{:error, :not_found}`.
  """
  @spec get_conversation(atom(), String.t()) ::
          {:ok, Conversation.t()} | {:error, :not_found | term()}
  def get_conversation(store, id) do
    Store.load_conversation(id, store: store)
  end

  @doc """
  Creates a new conversation.

  Accepts a map of attributes which will be used to build a
  `PhoenixAI.Store.Conversation` struct. The Store will generate
  UUIDs and timestamps automatically.

  ## Attrs

  - `:title` — conversation title
  - `:user_id` — owning user ID
  - `:model` — AI model identifier
  - `:tags` — list of string tags
  - `:metadata` — arbitrary metadata map

  Returns `{:ok, conversation}` or `{:error, reason}`.
  """
  @spec create_conversation(atom(), map()) :: {:ok, Conversation.t()} | {:error, term()}
  def create_conversation(store, attrs) when is_map(attrs) do
    conv = %Conversation{
      title: Map.get(attrs, :title),
      user_id: Map.get(attrs, :user_id),
      model: Map.get(attrs, :model),
      tags: Map.get(attrs, :tags, []),
      metadata: Map.get(attrs, :metadata, %{})
    }

    Store.save_conversation(conv, store: store)
  end

  @doc """
  Updates an existing conversation by ID.

  Loads the conversation, merges the given attrs, then saves it back.
  Only the following keys are merged: `:title`, `:user_id`, `:model`,
  `:tags`, `:metadata`.

  Returns `{:ok, updated_conversation}` or `{:error, reason}`.
  """
  @spec update_conversation(atom(), String.t(), map()) ::
          {:ok, Conversation.t()} | {:error, term()}
  def update_conversation(store, id, attrs) when is_map(attrs) do
    with {:ok, conv} <- Store.load_conversation(id, store: store) do
      updated =
        conv
        |> maybe_put(:title, attrs)
        |> maybe_put(:user_id, attrs)
        |> maybe_put(:model, attrs)
        |> maybe_put(:tags, attrs)
        |> maybe_put(:metadata, attrs)

      Store.save_conversation(updated, store: store)
    end
  end

  @doc """
  Deletes a conversation by ID.

  The Store handles soft-delete internally based on its configuration.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec delete_conversation(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_conversation(store, id, _opts \\ []) do
    Store.delete_conversation(id, store: store)
  end

  @doc """
  Counts conversations matching the given filters.

  Returns `{:ok, count}` or `{:error, reason}`.
  """
  @spec count_conversations(atom(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_conversations(store, filters \\ []) do
    Store.count_conversations(filters, store: store)
  end

  # -------------------------------------------------------------------
  # Messages
  # -------------------------------------------------------------------

  @doc """
  Lists messages for a conversation.

  The Store returns all messages ordered by `inserted_at`. This function
  applies client-side pagination via `:limit` and `:before_cursor` opts
  to support lazy-loading in the UI.

  ## Options

  - `:limit` — max number of messages to return (default: 20)
  - `:before_cursor` — return messages inserted before this ISO 8601
    datetime string (cursor-based pagination)

  Returns `{:ok, {messages, next_cursor}}` where `next_cursor` is `nil`
  when there are no more messages to load.
  """
  @spec list_messages(atom(), String.t(), keyword()) ::
          {:ok, {[Message.t()], String.t() | nil}} | {:error, term()}
  def list_messages(store, conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    before_cursor = Keyword.get(opts, :before_cursor)

    with {:ok, all_messages} <- Store.get_messages(conversation_id, store: store) do
      filtered =
        if before_cursor do
          {:ok, cursor_dt, _} = DateTime.from_iso8601(before_cursor)

          Enum.filter(all_messages, fn msg ->
            msg.inserted_at != nil and DateTime.compare(msg.inserted_at, cursor_dt) == :lt
          end)
        else
          all_messages
        end

      # Messages are ordered ascending by inserted_at from the store.
      # For "load older" pagination we take from the tail (most recent first),
      # so we reverse, take limit, then reverse back to chronological order.
      total = length(filtered)

      page =
        filtered
        |> Enum.reverse()
        |> Enum.take(limit)
        |> Enum.reverse()

      next_cursor =
        if total > limit do
          page
          |> List.first()
          |> case do
            %{inserted_at: %DateTime{} = dt} -> DateTime.to_iso8601(dt)
            _ -> nil
          end
        else
          nil
        end

      {:ok, {page, next_cursor}}
    end
  end

  # -------------------------------------------------------------------
  # Streaming / Converse
  # -------------------------------------------------------------------

  @doc """
  Sends a user message within a conversation and gets an AI response.

  Delegates to `PhoenixAI.Store.converse/3` which handles the full
  pipeline: saving the user message, loading history, applying memory,
  running guardrails, calling the AI provider, and saving the response.

  ## Options

  - `:provider` — AI provider atom
  - `:model` — model string
  - `:api_key` — API key override
  - `:system` — system prompt
  - `:tools` — tool definitions
  - `:memory_pipeline` — memory pipeline struct
  - `:guardrails` — guardrail policy entries
  - `:user_id` — user identifier

  Returns `{:ok, response}` or `{:error, reason}`.
  """
  @spec converse(atom(), String.t(), String.t(), keyword()) ::
          {:ok, PhoenixAI.Response.t()} | {:error, term()}
  def converse(store, conversation_id, message, opts \\ []) do
    Store.converse(conversation_id, message, Keyword.put(opts, :store, store))
  end

  # -------------------------------------------------------------------
  # Conversation stats
  # -------------------------------------------------------------------

  @doc "Loads a conversation with computed message_count and total_cost."
  @spec get_conversation_with_stats(atom(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_conversation_with_stats(store, id) do
    with {:ok, conversation} <- get_conversation(store, id) do
      stats = build_stats(store, conversation)
      {:ok, Map.merge(Map.from_struct(conversation), stats)}
    end
  end

  @doc "Lists all conversations with computed stats for table display."
  @spec list_conversations_with_stats(atom(), keyword()) :: [map()]
  def list_conversations_with_stats(store, opts \\ []) do
    case list_conversations(store, opts) do
      {:ok, conversations} ->
        Enum.map(conversations, fn conv ->
          stats = build_stats(store, conv)
          Map.merge(Map.from_struct(conv), stats)
        end)

      {:error, _} ->
        []
    end
  end

  # -------------------------------------------------------------------
  # Store info
  # -------------------------------------------------------------------

  @doc """
  Returns the backend type for the given store.

  Returns `:ets` or `:ecto` (or `:unknown` for unrecognized adapters).
  """
  @spec backend_type(atom()) :: :ets | :ecto | :unknown
  def backend_type(store) do
    config = PhoenixAI.Store.Instance.get_config(store)

    case config[:adapter] do
      PhoenixAI.Store.Adapters.ETS -> :ets
      PhoenixAI.Store.Adapters.Ecto -> :ecto
      _ -> :unknown
    end
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp build_stats(store, conversation) do
    message_count = length(conversation.messages || [])
    total_cost = compute_total_cost(store, conversation.id)
    status = if conversation.deleted_at, do: :deleted, else: :active

    %{
      message_count: message_count,
      total_cost: total_cost,
      status: status
    }
  end

  defp compute_total_cost(store, conversation_id) do
    case Store.sum_cost([conversation_id: conversation_id], store: store) do
      {:ok, total} -> total
      {:error, _} -> Decimal.new("0")
    end
  end

  defp maybe_put(struct, key, attrs) do
    if Map.has_key?(attrs, key) do
      Map.put(struct, key, Map.get(attrs, key))
    else
      struct
    end
  end
end
