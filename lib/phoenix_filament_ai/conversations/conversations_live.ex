defmodule PhoenixFilamentAI.ConversationsLive do
  @moduledoc """
  LiveView handling both index and show views for AI conversations.

  ## Routes

  - `/ai/conversations` — index view (table of all conversations)
  - `/ai/conversations/:id` — show view (thread + metadata sidebar)

  ## Assigns

  - `:view` — `:index` or `:show`
  - `:conversations` — list of conversation maps with stats (index view)
  - `:conversation` — single conversation map with stats (show view)
  - `:editing` — `nil`, `:title`, or `:tags` (inline edit state)
  - `:table_params` — query params forwarded to InMemoryTableLive
  - `:config` — plugin config
  - `:store` — store atom
  """

  use Phoenix.LiveView

  alias PhoenixFilamentAI.Conversations.Exporter
  alias PhoenixFilamentAI.StoreAdapter
  alias PhoenixFilament.Column
  alias PhoenixFilament.Table.{Action, Filter}
  alias PhoenixFilament.Table.InMemoryTableLive

  require Logger

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    config = socket.assigns[:ai_config] || default_config()
    store = config[:store]

    {:ok,
     socket
     |> assign(:config, config)
     |> assign(:store, store)
     |> assign(:view, :index)
     |> assign(:conversations, [])
     |> assign(:conversation, nil)
     |> assign(:editing, nil)
     |> assign(:table_params, %{})
     |> assign(:page_title, "Conversations")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case params do
      %{"id" => id} ->
        socket = load_conversation(socket, id)
        {:noreply, assign(socket, :view, :show)}

      _ ->
        conversations = load_conversations(socket.assigns.store)
        table_params = Map.drop(params, ["id"])

        {:noreply,
         socket
         |> assign(:view, :index)
         |> assign(:conversation, nil)
         |> assign(:editing, nil)
         |> assign(:conversations, conversations)
         |> assign(:table_params, table_params)}
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("edit_start", %{"field" => field}, socket) do
    {:noreply, assign(socket, :editing, String.to_existing_atom(field))}
  end

  def handle_event("edit_cancel", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("edit_save", %{"field" => "title", "value" => value}, socket) do
    store = socket.assigns.store
    conversation = socket.assigns.conversation

    case StoreAdapter.update_conversation(store, conversation.id, %{title: value}) do
      {:ok, _updated} ->
        socket = load_conversation(socket, conversation.id)
        {:noreply, assign(socket, :editing, nil)}

      {:error, reason} ->
        Logger.error("Failed to update conversation title: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to update title")}
    end
  end

  def handle_event("edit_save", %{"field" => "tags", "value" => value}, socket) do
    store = socket.assigns.store
    conversation = socket.assigns.conversation

    tags =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case StoreAdapter.update_conversation(store, conversation.id, %{tags: tags}) do
      {:ok, _updated} ->
        socket = load_conversation(socket, conversation.id)
        {:noreply, assign(socket, :editing, nil)}

      {:error, reason} ->
        Logger.error("Failed to update conversation tags: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to update tags")}
    end
  end

  def handle_event("export_json", _params, socket) do
    conversation = socket.assigns.conversation
    content = Exporter.to_json(conversation)
    filename = export_filename(conversation, "json")

    {:noreply,
     push_event(socket, "pfa:download", %{
       content: Base.encode64(content),
       filename: filename,
       content_type: "application/json"
     })}
  end

  def handle_event("export_markdown", _params, socket) do
    conversation = socket.assigns.conversation
    content = Exporter.to_markdown(conversation)
    filename = export_filename(conversation, "md")

    {:noreply,
     push_event(socket, "pfa:download", %{
       content: Base.encode64(content),
       filename: filename,
       content_type: "text/markdown"
     })}
  end

  def handle_event("delete_conversation", %{"id" => id}, socket) do
    store = socket.assigns.store

    case StoreAdapter.delete_conversation(store, id) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Conversation deleted")

        {:noreply, push_patch(socket, to: conversations_path())}

      {:error, reason} ->
        Logger.error("Failed to delete conversation: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to delete conversation")}
    end
  end

  # ---------------------------------------------------------------------------
  # Info — InMemoryTableLive routing
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:table_patch, query_string}, socket) do
    {:noreply, push_patch(socket, to: "#{conversations_path()}?#{query_string}")}
  end

  def handle_info({:table_action, :view, id}, socket) do
    {:noreply, push_patch(socket, to: conversations_path(id))}
  end

  def handle_info({:table_action, :delete, id}, socket) do
    store = socket.assigns.store

    case StoreAdapter.delete_conversation(store, id) do
      :ok ->
        conversations = load_conversations(store)

        {:noreply,
         socket
         |> assign(:conversations, conversations)
         |> put_flash(:info, "Conversation deleted")}

      {:error, reason} ->
        Logger.error("Failed to delete conversation: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to delete conversation")}
    end
  end

  # Ignore unhandled messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(%{view: :index} = assigns) do
    ~H"""
    <div class="pfa-conversations-page">
      <div class="pfa-conversations-header">
        <h1 class="pfa-conversations-title">Conversations</h1>
      </div>

      <.live_component
        module={InMemoryTableLive}
        id="conversations-table"
        rows={@conversations}
        columns={columns()}
        filters={filters()}
        actions={actions()}
        params={@table_params}
        empty_message="No conversations yet. Start chatting to see conversations here."
      />
    </div>
    """
  end

  def render(%{view: :show, conversation: nil} = assigns) do
    ~H"""
    <div class="pfa-conversations-page">
      <.link patch={conversations_path()} class="pfa-conversations-back">
        &larr; Back to conversations
      </.link>
      <p>Conversation not found.</p>
    </div>
    """
  end

  def render(%{view: :show} = assigns) do
    ~H"""
    <div class="pfa-conversations-page" id="conversations-show" phx-hook="PfaDownload">
      <.link patch={conversations_path()} class="pfa-conversations-back">
        &larr; Back to conversations
      </.link>

      <div class="pfa-conversations-show">
        <%!-- Thread area (~75%) --%>
        <div class="pfa-conversations-thread">
          <div class="pfa-conversations-messages">
            <%= for message <- (@conversation.messages || []) do %>
              <div class="pfa-message-wrapper">
                <div class="pfa-message-timestamp">{format_time(message.inserted_at)}</div>
                <PhoenixFilamentAI.Components.MessageComponent.message
                  message={message}
                  streaming={false}
                />
                <div
                  :if={message.role == :assistant && message.token_count && message.token_count > 0}
                  class="pfa-message-tokens"
                >
                  {format_number(message.token_count)} tokens
                </div>
              </div>
            <% end %>
          </div>

          <div class="pfa-conversations-cost-summary">
            Total cost: $<span class="pfa-cost-value">{format_cost(@conversation[:total_cost])}</span>
          </div>
        </div>

        <%!-- Metadata sidebar (~25%) --%>
        <div class="pfa-conversations-sidebar">
          <%!-- Title --%>
          <div class="pfa-meta-field">
            <label class="pfa-meta-label">Title</label>
            <%= if @editing == :title do %>
              <form phx-submit="edit_save">
                <input type="hidden" name="field" value="title" />
                <input
                  type="text"
                  name="value"
                  value={@conversation.title}
                  class="pfa-meta-input"
                  phx-keydown="edit_cancel"
                  phx-key="Escape"
                  autofocus
                />
                <button type="submit" class="pfa-meta-save-btn">Save</button>
                <button type="button" phx-click="edit_cancel" class="pfa-meta-cancel-btn">
                  Cancel
                </button>
              </form>
            <% else %>
              <div
                class="pfa-meta-value pfa-meta-editable"
                phx-click="edit_start"
                phx-value-field="title"
              >
                {@conversation.title || "Untitled"}
              </div>
            <% end %>
          </div>

          <%!-- Tags --%>
          <div class="pfa-meta-field">
            <label class="pfa-meta-label">Tags</label>
            <%= if @editing == :tags do %>
              <form phx-submit="edit_save">
                <input type="hidden" name="field" value="tags" />
                <input
                  type="text"
                  name="value"
                  value={Enum.join(@conversation.tags || [], ", ")}
                  class="pfa-meta-input"
                  placeholder="tag1, tag2, tag3"
                  phx-keydown="edit_cancel"
                  phx-key="Escape"
                  autofocus
                />
                <button type="submit" class="pfa-meta-save-btn">Save</button>
                <button type="button" phx-click="edit_cancel" class="pfa-meta-cancel-btn">
                  Cancel
                </button>
              </form>
            <% else %>
              <div
                class="pfa-meta-value pfa-meta-editable"
                phx-click="edit_start"
                phx-value-field="tags"
              >
                <%= if Enum.empty?(@conversation.tags || []) do %>
                  <span class="pfa-meta-empty">No tags</span>
                <% else %>
                  <%= for tag <- @conversation.tags do %>
                    <span class="pfa-tag">{tag}</span>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Read-only metadata --%>
          <div class="pfa-meta-field">
            <label class="pfa-meta-label">Model</label>
            <div class="pfa-meta-value">{@conversation.model || "—"}</div>
          </div>

          <div class="pfa-meta-field">
            <label class="pfa-meta-label">Messages</label>
            <div class="pfa-meta-value">{@conversation[:message_count] || length(@conversation.messages || [])}</div>
          </div>

          <div class="pfa-meta-field">
            <label class="pfa-meta-label">Total Cost</label>
            <div class="pfa-meta-value">${format_cost(@conversation[:total_cost])}</div>
          </div>

          <div class="pfa-meta-field">
            <label class="pfa-meta-label">Total Tokens</label>
            <div class="pfa-meta-value">{format_number(total_tokens(@conversation))}</div>
          </div>

          <div class="pfa-meta-field">
            <label class="pfa-meta-label">Created</label>
            <div class="pfa-meta-value">{format_datetime(@conversation.inserted_at)}</div>
          </div>

          <div class="pfa-meta-field">
            <label class="pfa-meta-label">Updated</label>
            <div class="pfa-meta-value">{format_datetime(@conversation.updated_at)}</div>
          </div>

          <%!-- Export actions --%>
          <div class="pfa-meta-actions">
            <button phx-click="export_json" class="pfa-meta-btn pfa-meta-btn--secondary">
              Export JSON
            </button>
            <button phx-click="export_markdown" class="pfa-meta-btn pfa-meta-btn--secondary">
              Export Markdown
            </button>
          </div>

          <%!-- Delete --%>
          <div class="pfa-meta-danger">
            <button
              phx-click="delete_conversation"
              phx-value-id={@conversation.id}
              data-confirm="Are you sure you want to delete this conversation? This cannot be undone."
              class="pfa-meta-btn pfa-meta-btn--danger"
            >
              Delete Conversation
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private — table config
  # ---------------------------------------------------------------------------

  defp columns do
    [
      Column.new(:title,
        label: "Title",
        sortable: true,
        searchable: true
      ),
      Column.new(:user_id,
        label: "User",
        sortable: true,
        searchable: true
      ),
      Column.new(:message_count,
        label: "Messages",
        sortable: true,
        format: fn val, _row -> format_number(val) end
      ),
      Column.new(:total_cost,
        label: "Cost",
        sortable: true,
        format: fn val, _row -> "$#{format_cost(val)}" end
      ),
      Column.new(:tags,
        label: "Tags",
        format: fn val, _row ->
          case val do
            tags when is_list(tags) and tags != [] -> Enum.join(tags, ", ")
            _ -> "—"
          end
        end
      ),
      Column.new(:status,
        label: "Status",
        badge: true,
        format: fn val, _row -> to_string(val) end
      ),
      Column.new(:inserted_at,
        label: "Created",
        sortable: true,
        format: fn val, _row -> format_date(val) end
      )
    ]
  end

  defp filters do
    [
      %Filter{
        type: :select,
        field: :status,
        label: "Status",
        options: [{"All", ""}, {"Active", "active"}, {"Deleted", "deleted"}]
      },
      %Filter{
        type: :date_range,
        field: :inserted_at,
        label: "Created"
      }
    ]
  end

  defp actions do
    [
      %Action{type: :view, label: "View", icon: "hero-eye"},
      %Action{
        type: :delete,
        label: "Delete",
        icon: "hero-trash",
        confirm: "Are you sure you want to delete this conversation?"
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Private — data loading
  # ---------------------------------------------------------------------------

  defp load_conversations(store) do
    StoreAdapter.list_conversations_with_stats(store)
  end

  defp load_conversation(socket, id) do
    store = socket.assigns.store

    case StoreAdapter.get_conversation_with_stats(store, id) do
      {:ok, conversation} ->
        assign(socket, :conversation, conversation)

      {:error, reason} ->
        Logger.error("Failed to load conversation #{id}: #{inspect(reason)}")
        assign(socket, :conversation, nil)
    end
  end

  # ---------------------------------------------------------------------------
  # Private — format helpers
  # ---------------------------------------------------------------------------

  defp format_cost(nil), do: "0.00"

  defp format_cost(%Decimal{} = d) do
    d |> Decimal.round(2) |> Decimal.to_string()
  end

  defp format_cost(other), do: to_string(other)

  defp format_date(nil), do: "—"

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y")
  end

  defp format_date(_), do: "—"

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end

  defp format_datetime(_), do: "—"

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_time(_), do: ""

  defp format_number(nil), do: "0"

  defp format_number(n) when is_integer(n) do
    n |> Integer.to_string() |> format_integer_string()
  end

  defp format_number(n), do: to_string(n)

  defp format_integer_string(str) do
    str |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
  end

  defp total_tokens(conversation) do
    (conversation.messages || [])
    |> Enum.reduce(0, fn msg, acc ->
      case msg.token_count do
        nil -> acc
        n when is_integer(n) -> acc + n
        _ -> acc
      end
    end)
  end

  defp export_filename(conversation, ext) do
    id = conversation.id || "unknown"
    "conversation-#{id}.#{ext}"
  end

  # ---------------------------------------------------------------------------
  # Private — routing helpers
  # ---------------------------------------------------------------------------

  defp conversations_path, do: "/ai/conversations"
  defp conversations_path(id), do: "/ai/conversations/#{id}"

  defp default_config do
    [store: nil, provider: nil, model: nil, chat: []]
  end
end
