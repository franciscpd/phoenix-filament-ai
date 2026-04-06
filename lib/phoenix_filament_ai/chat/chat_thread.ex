defmodule PhoenixFilamentAI.Chat.ChatThread do
  @moduledoc """
  Stateful LiveComponent that manages a chat conversation thread.

  Shared between `ChatWidget` and `ChatPage`. Handles:

  - Message list rendering with lazy loading
  - User input and submission
  - AI response lifecycle (loading, streaming, error)
  - Retry on failure
  - Empty state with clickable suggestions

  ## Required Assigns

  - `:id` — unique component ID
  - `:store` — store name atom (e.g. `:my_store`)
  - `:config` — validated plugin config keyword list

  ## Optional Assigns

  - `:conversation_id` — existing conversation ID (`nil` = new conversation)
  - `:stream_mode` — streaming strategy (default `:parent_routed`)
    - `:parent_routed` — parent LiveView manages the Task and routes chunks
      via `send_update`. Use when parent handles `{:start_ai_stream, ...}`.
    - `:self_managed` — ChatThread manages its own Task with `on_chunk`
      callback. Use inside widgets where the parent doesn't route messages.
  """

  use Phoenix.LiveComponent

  alias PhoenixFilamentAI.Chat.StreamHandler
  alias PhoenixFilamentAI.Components.{MessageComponent, TypingIndicator}
  alias PhoenixFilamentAI.StoreAdapter

  require Logger

  @default_suggestions [
    "How many users signed up this week?",
    "Summarize recent orders",
    "What's the conversion rate?"
  ]

  @messages_per_page 20

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:streaming, false)
     |> assign(:current_response, "")
     |> assign(:input_value, "")
     |> assign(:has_more, false)
     |> assign(:cursor, nil)
     |> assign(:last_message_for_retry, nil)
     |> assign(:task_ref, nil)
     |> assign_new(:stream_mode, fn -> :parent_routed end)}
  end

  @impl true
  def update(assigns, socket) do
    # Process streaming assigns from parent (via send_update) before normal merge.
    # These are routed by the parent LiveView which receives handle_info messages.
    socket =
      cond do
        Map.has_key?(assigns, :ai_chunk) ->
          handle_ai_chunk(assigns.ai_chunk, socket)

        Map.has_key?(assigns, :ai_complete) ->
          handle_ai_complete(assigns.ai_complete, socket)

        Map.has_key?(assigns, :ai_error) ->
          handle_ai_error(assigns.ai_error, socket)

        true ->
          socket
      end

    # Drop streaming keys before merge to avoid stale assigns
    clean_assigns = Map.drop(assigns, [:ai_chunk, :ai_complete, :ai_error])
    socket = assign(socket, clean_assigns)

    socket =
      if assign_changed?(socket, :conversation_id) do
        load_conversation(socket)
      else
        socket
      end

    {:ok, socket}
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      {:noreply, send_user_message(socket, message)}
    end
  end

  def handle_event("suggestion_click", %{"suggestion" => suggestion}, socket) do
    {:noreply, send_user_message(socket, suggestion)}
  end

  def handle_event("retry", _params, socket) do
    case socket.assigns.last_message_for_retry do
      nil ->
        {:noreply, socket}

      message ->
        # Remove the error message from the list
        messages =
          Enum.reject(socket.assigns.messages, fn msg ->
            msg.role == :error
          end)

        socket =
          socket
          |> assign(:messages, messages)
          |> send_user_message(message)

        {:noreply, socket}
    end
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, load_older_messages(socket)}
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-chat-thread" id={@id}>
      <div class="pfa-chat-messages" id={"#{@id}-messages"} phx-hook="ChatScroll">
        <button
          :if={@has_more}
          class="pfa-load-more-btn"
          phx-click="load_more"
          phx-target={@myself}
        >
          Load older messages
        </button>

        <%= if @messages == [] and not @streaming do %>
          <div class="pfa-empty-state">
            <p class="pfa-empty-state-text">Ask anything about your panel</p>
            <div class="pfa-suggestions">
              <button
                :for={suggestion <- suggestions()}
                class="pfa-suggestion-btn"
                phx-click="suggestion_click"
                phx-value-suggestion={suggestion}
                phx-target={@myself}
              >
                {suggestion}
              </button>
            </div>
          </div>
        <% else %>
          <div :for={msg <- @messages} class="pfa-message-wrapper">
            <MessageComponent.message
              message={msg}
              streaming={msg.role == :assistant and @streaming and msg == List.last(@messages)}
              on_retry={if(msg.role == :error, do: "retry")}
            />
          </div>

          <%= if @streaming and @current_response == "" do %>
            <TypingIndicator.typing_indicator />
          <% end %>
        <% end %>
      </div>

      <form
        class="pfa-chat-input-form"
        phx-submit="send_message"
        phx-target={@myself}
      >
        <textarea
          name="message"
          class="pfa-chat-input"
          placeholder="Type a message..."
          rows="1"
          disabled={@streaming}
          phx-hook="ChatInput"
          id={"#{@id}-input"}
        >{@input_value}</textarea>
        <button
          type="submit"
          class="pfa-chat-send-btn"
          disabled={@streaming}
        >
          Send
        </button>
      </form>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private — Message Handling
  # -------------------------------------------------------------------

  defp send_user_message(socket, message) do
    user_msg = %{role: :user, content: message, id: generate_id()}

    socket
    |> assign(:input_value, "")
    |> assign(:last_message_for_retry, message)
    |> update(:messages, &(&1 ++ [user_msg]))
    |> start_ai_call(message)
  end

  defp start_ai_call(socket, message) do
    store = socket.assigns.store
    conversation_id = socket.assigns.conversation_id
    config = socket.assigns.config

    converse_opts =
      [
        provider: Keyword.get(config, :provider),
        model: Keyword.get(config, :model),
        system: get_system_prompt(config),
        api_key: Keyword.get(config, :api_key)
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    if conversation_id do
      launch_stream(socket, store, conversation_id, message, converse_opts)
    else
      # No conversation yet — create one first, then converse
      case StoreAdapter.create_conversation(store, %{title: truncate(message, 50)}) do
        {:ok, conv} ->
          socket
          |> assign(:conversation_id, conv.id)
          |> launch_stream(store, conv.id, message, converse_opts)

        {:error, reason} ->
          Logger.error("Failed to create conversation: #{inspect(reason)}")
          add_error_message(socket, reason)
      end
    end
  end

  # :parent_routed — parent LiveView handles Task and routes messages via send_update.
  # Used when parent is a LiveView we control (e.g. ChatPage).
  defp launch_stream(
         %{assigns: %{stream_mode: :parent_routed}} = socket,
         store,
         conv_id,
         message,
         opts
       ) do
    send(self(), {:start_ai_stream, store, conv_id, message, opts})

    socket
    |> assign(:streaming, true)
    |> assign(:current_response, "")
  end

  # :self_managed — ChatThread manages its own streaming process.
  # Used when parent doesn't know about streaming (e.g. dashboard widgets).
  # Uses a simple spawn (no link) so a crash won't take down the LiveView.
  # The on_chunk callback calls send_update directly to route chunks back.
  # Completion/error is also routed via send_update from the spawned process.
  defp launch_stream(
         %{assigns: %{stream_mode: :self_managed}} = socket,
         store,
         conv_id,
         message,
         opts
       ) do
    component_id = socket.assigns.id
    parent_pid = self()

    spawn(fn ->
      result =
        StoreAdapter.converse(
          store,
          conv_id,
          message,
          Keyword.merge(opts,
            on_chunk: fn chunk ->
              send_update(parent_pid, __MODULE__, id: component_id, ai_chunk: chunk)
            end
          )
        )

      case result do
        {:ok, response} ->
          send_update(parent_pid, __MODULE__, id: component_id, ai_complete: response)

        {:error, reason} ->
          send_update(parent_pid, __MODULE__, id: component_id, ai_error: reason)
      end
    end)

    socket
    |> assign(:streaming, true)
    |> assign(:current_response, "")
  end

  # -------------------------------------------------------------------
  # Private — Conversation Loading
  # -------------------------------------------------------------------

  defp load_conversation(socket) do
    case socket.assigns do
      %{conversation_id: nil} ->
        assign(socket, messages: [], has_more: false, cursor: nil)

      %{conversation_id: conv_id, store: store} ->
        case StoreAdapter.list_messages(store, conv_id, limit: @messages_per_page) do
          {:ok, {messages, next_cursor}} ->
            formatted = Enum.map(messages, &format_store_message/1)

            socket
            |> assign(:messages, formatted)
            |> assign(:has_more, next_cursor != nil)
            |> assign(:cursor, next_cursor)

          {:error, reason} ->
            Logger.error("Failed to load messages: #{inspect(reason)}")
            assign(socket, messages: [], has_more: false, cursor: nil)
        end
    end
  end

  defp load_older_messages(socket) do
    %{conversation_id: conv_id, store: store, cursor: cursor, messages: existing} =
      socket.assigns

    if conv_id && cursor do
      case StoreAdapter.list_messages(store, conv_id,
             limit: @messages_per_page,
             before_cursor: cursor
           ) do
        {:ok, {older_messages, next_cursor}} ->
          formatted = Enum.map(older_messages, &format_store_message/1)

          socket
          |> assign(:messages, formatted ++ existing)
          |> assign(:has_more, next_cursor != nil)
          |> assign(:cursor, next_cursor)

        {:error, _reason} ->
          socket
      end
    else
      socket
    end
  end

  defp format_store_message(msg) do
    %{
      role: msg.role,
      content: msg.content || "",
      id: msg.id
    }
  end

  # -------------------------------------------------------------------
  # Private — AI Response Handling (called from parent LiveView)
  # -------------------------------------------------------------------

  defp handle_ai_complete(response, socket) do
    assistant_msg = %{
      role: :assistant,
      content: response.content || "",
      id: generate_id()
    }

    # Replace the streaming placeholder if present, otherwise append
    messages =
      case List.last(socket.assigns.messages) do
        %{id: "streaming"} ->
          List.replace_at(
            socket.assigns.messages,
            length(socket.assigns.messages) - 1,
            assistant_msg
          )

        _ ->
          socket.assigns.messages ++ [assistant_msg]
      end

    socket
    |> assign(:streaming, false)
    |> assign(:current_response, "")
    |> assign(:task_ref, nil)
    |> assign(:messages, messages)
  end

  defp handle_ai_chunk(chunk, socket) do
    new_content = socket.assigns.current_response <> (chunk.delta || "")

    # Update or append the streaming assistant message
    messages = update_streaming_message(socket.assigns.messages, new_content)

    socket
    |> assign(:current_response, new_content)
    |> assign(:messages, messages)
  end

  defp handle_ai_error(reason, socket) do
    # Remove the streaming placeholder if present
    messages = Enum.reject(socket.assigns.messages, &(&1.id == "streaming"))

    socket
    |> assign(:streaming, false)
    |> assign(:current_response, "")
    |> assign(:task_ref, nil)
    |> assign(:messages, messages)
    |> add_error_message(reason)
  end

  defp update_streaming_message(messages, content) do
    streaming_msg = %{role: :assistant, content: content, id: "streaming"}

    case List.last(messages) do
      %{id: "streaming"} ->
        List.replace_at(messages, length(messages) - 1, streaming_msg)

      _ ->
        messages ++ [streaming_msg]
    end
  end

  defp add_error_message(socket, reason) do
    error_msg = %{
      role: :error,
      content: StreamHandler.error_message(reason),
      id: generate_id()
    }

    update(socket, :messages, &(&1 ++ [error_msg]))
  end

  # -------------------------------------------------------------------
  # Private — Helpers
  # -------------------------------------------------------------------

  defp get_system_prompt(config) do
    cond do
      prompt = get_in(config, [:chat, :system_prompt]) -> prompt
      is_list(config[:chat_widget]) -> Keyword.get(config[:chat_widget], :system_prompt)
      true -> nil
    end
  end

  defp suggestions, do: @default_suggestions

  defp generate_id do
    "msg-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp truncate(string, max_length) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length) <> "..."
    else
      string
    end
  end

  defp assign_changed?(socket, key) do
    case socket.assigns do
      %{__changed__: changes} when is_map(changes) ->
        Map.has_key?(changes, key)

      _ ->
        true
    end
  end
end
