defmodule PhoenixFilamentAI.Chat.ChatWidgetTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixFilamentAI.ChatWidget

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

  @config_with_custom_title Keyword.put(@valid_config, :chat_widget,
                              title: "Custom Bot",
                              column_span: 6,
                              sort: 100
                            )

  describe "rendering" do
    test "renders with default title 'AI Assistant'" do
      html =
        render_component(ChatWidget,
          id: "test-widget",
          config: @valid_config
        )

      assert html =~ "AI Assistant"
      assert html =~ "pfa-chat-widget"
    end

    test "contains ChatThread component (pfa-chat-thread class)" do
      html =
        render_component(ChatWidget,
          id: "test-widget",
          config: @valid_config
        )

      assert html =~ "pfa-chat-thread"
    end

    test "renders with custom title from config" do
      html =
        render_component(ChatWidget,
          id: "test-widget",
          config: @config_with_custom_title
        )

      assert html =~ "Custom Bot"
      assert html =~ "pfa-chat-widget"
    end

    test "renders header with new conversation button" do
      html =
        render_component(ChatWidget,
          id: "test-widget",
          config: @valid_config
        )

      assert html =~ "new_conversation"
      assert html =~ "pfa-chat-widget-header"
    end
  end
end
