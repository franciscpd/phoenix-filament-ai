defmodule PhoenixFilamentAI.Chat.ChatThreadTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.Chat.ChatThread

  @endpoint PhoenixFilamentAI.TestEndpoint

  @valid_config [
    store: :test_store,
    provider: :openai,
    model: "gpt-4o",
    chat_widget: true,
    chat_page: true,
    conversations: false,
    cost_dashboard: false,
    event_log: false,
    nav_group: "AI",
    nav_icon: "hero-sparkles",
    ets_warning: true,
    chat: []
  ]

  describe "render with empty state" do
    test "shows empty state with suggestions when no messages" do
      html =
        render_component(ChatThread,
          id: "test-thread",
          store: :test_store,
          config: @valid_config,
          conversation_id: nil
        )

      assert html =~ "pfa-empty-state"
      assert html =~ "Ask anything about your panel"
      assert html =~ "pfa-suggestion-btn"
      assert html =~ "How many users signed up this week?"
      assert html =~ "Summarize recent orders"
      assert html =~ "What&#39;s the conversion rate?"
    end

    test "renders chat input form" do
      html =
        render_component(ChatThread,
          id: "test-thread",
          store: :test_store,
          config: @valid_config,
          conversation_id: nil
        )

      assert html =~ "pfa-chat-input-form"
      assert html =~ "pfa-chat-input"
      assert html =~ "pfa-chat-send-btn"
      assert html =~ "Send"
      assert html =~ ~s(placeholder="Type a message...")
    end

    test "does not show load more button when no history" do
      html =
        render_component(ChatThread,
          id: "test-thread",
          store: :test_store,
          config: @valid_config,
          conversation_id: nil
        )

      refute html =~ "pfa-load-more-btn"
    end
  end

  describe "handle_ai_complete/2" do
    test "adds assistant message and clears streaming state" do
      socket =
        build_socket(%{
          messages: [%{role: :user, content: "Hello", id: "msg-1"}],
          streaming: true,
          current_response: "partial",
          task_ref: make_ref()
        })

      response = %{content: "Hello! How can I help?"}
      updated = ChatThread.handle_ai_complete(response, socket)

      assert updated.assigns.streaming == false
      assert updated.assigns.current_response == ""
      assert updated.assigns.task_ref == nil
      assert length(updated.assigns.messages) == 2

      last_msg = List.last(updated.assigns.messages)
      assert last_msg.role == :assistant
      assert last_msg.content == "Hello! How can I help?"
    end

    test "handles nil content in response" do
      socket =
        build_socket(%{
          messages: [],
          streaming: true,
          current_response: "",
          task_ref: make_ref()
        })

      response = %{content: nil}
      updated = ChatThread.handle_ai_complete(response, socket)

      last_msg = List.last(updated.assigns.messages)
      assert last_msg.content == ""
    end
  end

  describe "handle_ai_chunk/2" do
    test "accumulates chunk content and creates streaming message" do
      socket =
        build_socket(%{
          messages: [%{role: :user, content: "Hi", id: "msg-1"}],
          streaming: true,
          current_response: ""
        })

      chunk = %{delta: "Hello"}
      updated = ChatThread.handle_ai_chunk(chunk, socket)

      assert updated.assigns.current_response == "Hello"
      assert length(updated.assigns.messages) == 2

      streaming_msg = List.last(updated.assigns.messages)
      assert streaming_msg.role == :assistant
      assert streaming_msg.content == "Hello"
      assert streaming_msg.id == "streaming"
    end

    test "appends to existing streaming content" do
      socket =
        build_socket(%{
          messages: [
            %{role: :user, content: "Hi", id: "msg-1"},
            %{role: :assistant, content: "Hel", id: "streaming"}
          ],
          streaming: true,
          current_response: "Hel"
        })

      chunk = %{delta: "lo"}
      updated = ChatThread.handle_ai_chunk(chunk, socket)

      assert updated.assigns.current_response == "Hello"
      # Should still be 2 messages (user + streaming assistant)
      assert length(updated.assigns.messages) == 2

      streaming_msg = List.last(updated.assigns.messages)
      assert streaming_msg.content == "Hello"
    end

    test "handles nil delta gracefully" do
      socket =
        build_socket(%{
          messages: [%{role: :user, content: "Hi", id: "msg-1"}],
          streaming: true,
          current_response: "Hello"
        })

      chunk = %{delta: nil}
      updated = ChatThread.handle_ai_chunk(chunk, socket)

      assert updated.assigns.current_response == "Hello"
    end
  end

  describe "handle_ai_error/2" do
    test "adds error message and clears streaming state" do
      socket =
        build_socket(%{
          messages: [%{role: :user, content: "Hello", id: "msg-1"}],
          streaming: true,
          current_response: "partial",
          task_ref: make_ref()
        })

      updated = ChatThread.handle_ai_error(:timeout, socket)

      assert updated.assigns.streaming == false
      assert updated.assigns.current_response == ""
      assert updated.assigns.task_ref == nil
      assert length(updated.assigns.messages) == 2

      error_msg = List.last(updated.assigns.messages)
      assert error_msg.role == :error
      assert error_msg.content =~ "timed out"
    end

    test "handles fatal errors" do
      socket =
        build_socket(%{
          messages: [],
          streaming: true,
          current_response: "",
          task_ref: make_ref()
        })

      updated = ChatThread.handle_ai_error(:invalid_api_key, socket)

      error_msg = List.last(updated.assigns.messages)
      assert error_msg.role == :error
      assert error_msg.content =~ "Invalid API key"
    end
  end

  describe "component structure" do
    test "has the correct CSS class on root" do
      html =
        render_component(ChatThread,
          id: "my-thread",
          store: :test_store,
          config: @valid_config,
          conversation_id: nil
        )

      assert html =~ ~s(class="pfa-chat-thread")
      assert html =~ ~s(id="my-thread")
    end

    test "input is not disabled when not streaming" do
      html =
        render_component(ChatThread,
          id: "test-thread",
          store: :test_store,
          config: @valid_config,
          conversation_id: nil
        )

      # The textarea should not have the disabled attribute
      refute html =~ ~s(disabled)
    end
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp build_socket(assigns) do
    defaults = %{
      messages: [],
      streaming: false,
      current_response: "",
      input_value: "",
      has_more: false,
      cursor: nil,
      last_message_for_retry: nil,
      task_ref: nil,
      store: :test_store,
      config: @valid_config,
      conversation_id: nil,
      id: "test-thread",
      __changed__: %{}
    }

    merged = Map.merge(defaults, assigns)

    %Phoenix.LiveView.Socket{assigns: merged}
  end
end
