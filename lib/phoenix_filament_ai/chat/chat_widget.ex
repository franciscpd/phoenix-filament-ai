defmodule PhoenixFilamentAI.ChatWidget do
  @moduledoc """
  Dashboard chat widget that wraps `ChatThread` inside
  PhoenixFilament's widget system.

  Uses `PhoenixFilament.Widget.Custom` as its base, rendering a
  header bar (title, new-conversation button) and mounting
  `ChatThread` as a child LiveComponent.

  ## Configuration

  The widget reads its settings from the validated plugin config
  (`:chat_widget` key). Supported options:

  - `:title` — header text (default `"AI Assistant"`)
  - `:column_span` — grid column span (default `6`)
  - `:sort` — dashboard sort order (default `100`)
  """

  use PhoenixFilament.Widget.Custom

  alias PhoenixFilamentAI.Chat.ChatThread

  @default_title "AI Assistant"

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def update(assigns, socket) do
    config = assigns[:config] || []
    title = widget_title(config)

    socket =
      socket
      |> assign(assigns)
      |> assign(:title, title)
      |> assign_new(:conversation_id, fn -> nil end)

    {:ok, socket}
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:noreply, assign(socket, :conversation_id, nil)}
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-chat-widget" id={@id}>
      <div class="pfa-chat-widget-header">
        <h3 class="pfa-chat-widget-title">{@title}</h3>
        <div class="pfa-chat-widget-actions">
          <button
            type="button"
            class="pfa-chat-widget-btn"
            phx-click="new_conversation"
            phx-target={@myself}
            title="New conversation"
          >
            New
          </button>
        </div>
      </div>

      <div class="pfa-chat-widget-body">
        <.live_component
          module={ChatThread}
          id={"#{@id}-thread"}
          store={@config[:store]}
          config={@config}
          conversation_id={@conversation_id}
          stream_mode={:self_managed}
        />
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp widget_title(config) do
    case config[:chat_widget] do
      opts when is_list(opts) -> Keyword.get(opts, :title, @default_title)
      _ -> @default_title
    end
  end
end
