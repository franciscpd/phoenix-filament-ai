defmodule PhoenixFilamentAI.Chat.Sidebar do
  @moduledoc """
  Stateless function component for the conversation sidebar.

  Renders a list of conversations with search, active highlighting,
  and a "New Chat" button. Used by `PhoenixFilamentAI.ChatLive`.

  ## Required Assigns

  - `:conversations` — list of conversation maps/structs (each with `:id`, `:title`, `:inserted_at`)
  - `:active_conversation_id` — currently selected conversation ID (or `nil`)

  ## Optional Assigns

  - `:search_query` — current search filter text (default `""`)
  """

  use Phoenix.Component

  attr(:conversations, :list, required: true)
  attr(:active_conversation_id, :string, default: nil)
  attr(:search_query, :string, default: "")

  def sidebar(assigns) do
    ~H"""
    <aside class="pfa-sidebar">
      <div class="pfa-sidebar-header">
        <h2 class="pfa-sidebar-title">Conversations</h2>
      </div>

      <div class="pfa-sidebar-search">
        <form phx-change="sidebar_search" phx-submit="sidebar_search">
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder="Search conversations..."
            class="pfa-sidebar-search-input"
            autocomplete="off"
            phx-debounce="300"
          />
        </form>
      </div>

      <div class="pfa-sidebar-list">
        <%= if @conversations == [] do %>
          <div class="pfa-sidebar-empty">
            <p>Start your first conversation</p>
          </div>
        <% else %>
          <div
            :for={conv <- @conversations}
            class={"pfa-sidebar-item #{if conv.id == @active_conversation_id, do: "pfa-sidebar-item--active", else: ""}"}
            phx-click="select_conversation"
            phx-value-id={conv.id}
          >
            <div class="pfa-sidebar-item-title">{conv.title || "Untitled"}</div>
            <div class="pfa-sidebar-item-meta">
              <span :if={conv.inserted_at} class="pfa-sidebar-item-date">
                {format_date(conv.inserted_at)}
              </span>
              <span :if={Map.get(conv, :cost)} class="pfa-sidebar-item-cost">
                {format_cost(conv.cost)}
              </span>
            </div>
            <button
              type="button"
              class="pfa-sidebar-item-delete"
              phx-click="delete_conversation"
              phx-value-id={conv.id}
              title="Delete conversation"
            >
              &times;
            </button>
          </div>
        <% end %>
      </div>

      <div class="pfa-sidebar-footer">
        <button type="button" class="pfa-sidebar-new-btn" phx-click="new_conversation">
          New Chat
        </button>
      </div>
    </aside>
    """
  end

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y")
  end

  defp format_date(_), do: ""

  defp format_cost(cost) when is_number(cost) do
    "$#{:erlang.float_to_binary(cost / 1.0, decimals: 4)}"
  end

  defp format_cost(_), do: ""
end
