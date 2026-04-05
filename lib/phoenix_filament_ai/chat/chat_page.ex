defmodule PhoenixFilamentAI.ChatLive do
  @moduledoc """
  Full-screen LiveView for AI chat with a 2-column layout.

  Left column: conversation sidebar (search, list, new/delete).
  Right column: conversation header + `ChatThread` LiveComponent.

  ## Routes

  - `/ai/chat` — new conversation (no conversation selected)
  - `/ai/chat/:conversation_id` — existing conversation

  ## Assigns

  - `:conversations` — list of conversations from StoreAdapter
  - `:conversation_id` — currently selected conversation ID (or `nil`)
  - `:search_query` — sidebar search filter
  - `:config` — validated plugin config
  - `:store` — store atom
  """

  use Phoenix.LiveView

  alias PhoenixFilamentAI.Chat.{ChatThread, Sidebar}
  alias PhoenixFilamentAI.StoreAdapter

  require Logger

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    config = socket.assigns[:ai_config] || default_config()
    store = config[:store]

    conversations = load_conversations(store)

    {:ok,
     socket
     |> assign(:config, config)
     |> assign(:store, store)
     |> assign(:conversations, conversations)
     |> assign(:conversation_id, nil)
     |> assign(:search_query, "")
     |> assign(:page_title, "Chat")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    conversation_id = params["conversation_id"]

    {:noreply, assign(socket, :conversation_id, conversation_id)}
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  @impl true
  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: chat_path(id))}
  end

  def handle_event("new_conversation", _params, socket) do
    {:noreply, push_patch(socket, to: chat_path())}
  end

  def handle_event("sidebar_search", %{"query" => query}, socket) do
    filtered = filter_conversations(socket.assigns.store, query)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:conversations, filtered)}
  end

  def handle_event("delete_conversation", %{"id" => id}, socket) do
    store = socket.assigns.store

    case StoreAdapter.delete_conversation(store, id) do
      :ok ->
        conversations = load_conversations(store, socket.assigns.search_query)

        socket =
          socket
          |> assign(:conversations, conversations)
          |> put_flash(:info, "Conversation deleted")

        # If we deleted the active conversation, redirect to base chat
        if socket.assigns.conversation_id == id do
          {:noreply, push_patch(socket, to: chat_path())}
        else
          {:noreply, socket}
        end

      {:error, reason} ->
        Logger.error("Failed to delete conversation: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to delete conversation")}
    end
  end

  # -------------------------------------------------------------------
  # Info (forward AI messages to ChatThread)
  # -------------------------------------------------------------------

  @impl true
  def handle_info({:ai_complete, response}, socket) do
    send_update(ChatThread, id: "chat-thread", ai_complete: response)
    conversations = load_conversations(socket.assigns.store, socket.assigns.search_query)
    {:noreply, assign(socket, :conversations, conversations)}
  end

  def handle_info({:ai_error, reason}, socket) do
    send_update(ChatThread, id: "chat-thread", ai_error: reason)
    {:noreply, socket}
  end

  def handle_info({ref, result}, socket) when is_reference(ref) do
    # Task completion — forward to ChatThread
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, response} ->
        send_update(ChatThread, id: "chat-thread", ai_complete: response)
        conversations = load_conversations(socket.assigns.store, socket.assigns.search_query)
        {:noreply, assign(socket, :conversations, conversations)}

      {:error, reason} ->
        send_update(ChatThread, id: "chat-thread", ai_error: reason)
        {:noreply, socket}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-chat-page">
      <Sidebar.sidebar
        conversations={@conversations}
        active_conversation_id={@conversation_id}
        search_query={@search_query}
      />

      <div class="pfa-chat-main">
        <div class="pfa-chat-main-header">
          <h1 class="pfa-chat-main-title">
            {conversation_title(@conversations, @conversation_id)}
          </h1>
        </div>

        <.live_component
          module={ChatThread}
          id="chat-thread"
          store={@store}
          config={@config}
          conversation_id={@conversation_id}
        />
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp load_conversations(store, query \\ "") do
    case StoreAdapter.list_conversations(store) do
      {:ok, convs} ->
        convs
        |> maybe_filter_by_query(query)
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

      {:error, reason} ->
        Logger.error("Failed to load conversations: #{inspect(reason)}")
        []
    end
  end

  defp filter_conversations(store, query) do
    load_conversations(store, query)
  end

  defp maybe_filter_by_query(convs, query) when query in [nil, ""], do: convs

  defp maybe_filter_by_query(convs, query) do
    downcased = String.downcase(query)

    Enum.filter(convs, fn conv ->
      title = conv.title || ""
      String.contains?(String.downcase(title), downcased)
    end)
  end

  defp conversation_title(conversations, conversation_id) do
    case Enum.find(conversations, &(&1.id == conversation_id)) do
      %{title: title} when is_binary(title) and title != "" -> title
      _ -> "New Conversation"
    end
  end

  defp chat_path, do: "/ai/chat"
  defp chat_path(id), do: "/ai/chat/#{id}"

  defp default_config do
    [
      store: nil,
      provider: nil,
      model: nil,
      chat: []
    ]
  end
end
