defmodule PhoenixFilamentAI.Chat.ChatPageTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.Chat.Sidebar
  alias PhoenixFilamentAI.ChatLive

  @endpoint PhoenixFilamentAI.TestEndpoint

  # -------------------------------------------------------------------
  # Sidebar component tests
  # -------------------------------------------------------------------

  describe "Sidebar.sidebar/1" do
    test "renders empty state when no conversations" do
      html =
        render_component(&Sidebar.sidebar/1,
          conversations: [],
          active_conversation_id: nil,
          search_query: ""
        )

      assert html =~ "pfa-sidebar"
      assert html =~ "Conversations"
      assert html =~ "Start your first conversation"
      assert html =~ "New Chat"
    end

    test "renders conversation list" do
      conversations = [
        %{
          id: "conv-1",
          title: "First Chat",
          inserted_at: ~U[2026-01-15 10:00:00Z],
          cost: nil
        },
        %{
          id: "conv-2",
          title: "Second Chat",
          inserted_at: ~U[2026-01-16 12:00:00Z],
          cost: nil
        }
      ]

      html =
        render_component(&Sidebar.sidebar/1,
          conversations: conversations,
          active_conversation_id: nil,
          search_query: ""
        )

      assert html =~ "First Chat"
      assert html =~ "Second Chat"
      assert html =~ "pfa-sidebar-item"
      refute html =~ "Start your first conversation"
    end

    test "highlights active conversation" do
      conversations = [
        %{id: "conv-1", title: "Active Chat", inserted_at: ~U[2026-01-15 10:00:00Z], cost: nil},
        %{id: "conv-2", title: "Other Chat", inserted_at: ~U[2026-01-16 12:00:00Z], cost: nil}
      ]

      html =
        render_component(&Sidebar.sidebar/1,
          conversations: conversations,
          active_conversation_id: "conv-1",
          search_query: ""
        )

      assert html =~ "pfa-sidebar-item--active"
    end

    test "renders search input" do
      html =
        render_component(&Sidebar.sidebar/1,
          conversations: [],
          active_conversation_id: nil,
          search_query: ""
        )

      assert html =~ "pfa-sidebar-search-input"
      assert html =~ "sidebar_search"
      assert html =~ ~s(placeholder="Search conversations...")
    end

    test "renders new chat button" do
      html =
        render_component(&Sidebar.sidebar/1,
          conversations: [],
          active_conversation_id: nil,
          search_query: ""
        )

      assert html =~ "pfa-sidebar-new-btn"
      assert html =~ "New Chat"
      assert html =~ "new_conversation"
    end

    test "renders conversation date" do
      conversations = [
        %{id: "conv-1", title: "Dated Chat", inserted_at: ~U[2026-03-15 10:00:00Z], cost: nil}
      ]

      html =
        render_component(&Sidebar.sidebar/1,
          conversations: conversations,
          active_conversation_id: nil,
          search_query: ""
        )

      assert html =~ "Mar 15, 2026"
    end

    test "renders conversation cost when present" do
      conversations = [
        %{id: "conv-1", title: "Costly Chat", inserted_at: ~U[2026-01-15 10:00:00Z], cost: 0.0523}
      ]

      html =
        render_component(&Sidebar.sidebar/1,
          conversations: conversations,
          active_conversation_id: nil,
          search_query: ""
        )

      assert html =~ "$0.0523"
    end

    test "renders delete button for each conversation" do
      conversations = [
        %{id: "conv-1", title: "Chat", inserted_at: ~U[2026-01-15 10:00:00Z], cost: nil}
      ]

      html =
        render_component(&Sidebar.sidebar/1,
          conversations: conversations,
          active_conversation_id: nil,
          search_query: ""
        )

      assert html =~ "delete_conversation"
      assert html =~ "pfa-sidebar-item-delete"
    end

    test "shows Untitled for conversations without title" do
      conversations = [
        %{id: "conv-1", title: nil, inserted_at: ~U[2026-01-15 10:00:00Z], cost: nil}
      ]

      html =
        render_component(&Sidebar.sidebar/1,
          conversations: conversations,
          active_conversation_id: nil,
          search_query: ""
        )

      assert html =~ "Untitled"
    end

    test "renders current search query value" do
      html =
        render_component(&Sidebar.sidebar/1,
          conversations: [],
          active_conversation_id: nil,
          search_query: "hello"
        )

      assert html =~ ~s(value="hello")
    end
  end

  # -------------------------------------------------------------------
  # ChatLive unit-level tests (private helper behavior via render)
  # -------------------------------------------------------------------

  describe "ChatLive module" do
    test "module is defined and is a LiveView" do
      Code.ensure_loaded!(ChatLive)

      assert function_exported?(ChatLive, :mount, 3)
      assert function_exported?(ChatLive, :handle_params, 3)
      assert function_exported?(ChatLive, :handle_event, 3)
      assert function_exported?(ChatLive, :handle_info, 2)
      assert function_exported?(ChatLive, :render, 1)
    end
  end
end
