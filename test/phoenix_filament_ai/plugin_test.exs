defmodule PhoenixFilamentAI.PluginTest do
  use ExUnit.Case, async: true

  alias PhoenixFilament.AI

  import PhoenixFilamentAI.Fixtures

  describe "register/2" do
    test "returns map with all required keys" do
      result = AI.register(FakePanel, valid_plugin_opts())

      assert is_map(result)
      assert Map.has_key?(result, :nav_items)
      assert Map.has_key?(result, :routes)
      assert Map.has_key?(result, :widgets)
      assert Map.has_key?(result, :hooks)
      assert is_list(result.nav_items)
      assert is_list(result.routes)
      assert is_list(result.widgets)
      assert is_list(result.hooks)
    end

    test "includes chat navigation when chat_widget is enabled" do
      result = AI.register(FakePanel, valid_plugin_opts(chat_widget: true, chat_page: true))

      nav_labels = Enum.map(result.nav_items, & &1.label)
      assert "Chat" in nav_labels
    end

    test "includes chat route when chat_page is enabled" do
      result = AI.register(FakePanel, valid_plugin_opts(chat_page: true))

      route_paths = Enum.map(result.routes, & &1.path)
      assert "/ai/chat" in route_paths
    end

    test "excludes chat navigation when chat_page is disabled" do
      result = AI.register(FakePanel, valid_plugin_opts(chat_page: false))

      nav_labels = Enum.map(result.nav_items, & &1.label)
      refute "Chat" in nav_labels
    end

    test "excludes chat route when chat_page is disabled" do
      result = AI.register(FakePanel, valid_plugin_opts(chat_page: false))

      route_paths = Enum.map(result.routes, & &1.path)
      refute "/ai/chat" in route_paths
    end

    test "includes widget when chat_widget is enabled" do
      result = AI.register(FakePanel, valid_plugin_opts(chat_widget: true))

      assert length(result.widgets) >= 1
      widget = hd(result.widgets)
      assert Map.has_key?(widget, :module)
      assert Map.has_key?(widget, :sort)
      assert Map.has_key?(widget, :column_span)
    end

    test "excludes widget when chat_widget is disabled" do
      result = AI.register(FakePanel, valid_plugin_opts(chat_widget: false))

      assert result.widgets == []
    end

    test "widget respects keyword list options" do
      result =
        AI.register(FakePanel, valid_plugin_opts(chat_widget: [column_span: 8, sort: 50]))

      widget = hd(result.widgets)
      assert widget.column_span == 8
      assert widget.sort == 50
    end

    test "uses custom nav_group" do
      result = AI.register(FakePanel, valid_plugin_opts(nav_group: "Tools"))

      for item <- result.nav_items do
        assert item.nav_group == "Tools"
      end
    end

    test "uses default nav_group AI" do
      result = AI.register(FakePanel, valid_plugin_opts(chat_page: true))

      chat_nav = Enum.find(result.nav_items, &(&1.label == "Chat"))
      assert chat_nav.nav_group == "AI"
    end

    test "uses nav_icon for navigation items" do
      result =
        AI.register(FakePanel, valid_plugin_opts(chat_page: true, nav_icon: "hero-cpu-chip"))

      chat_nav = Enum.find(result.nav_items, &(&1.label == "Chat"))
      assert chat_nav.icon == "hero-cpu-chip"
    end

    test "includes conversations nav when enabled" do
      result = AI.register(FakePanel, valid_plugin_opts(conversations: true))

      nav_labels = Enum.map(result.nav_items, & &1.label)
      assert "Conversations" in nav_labels
    end

    test "excludes conversations nav when disabled" do
      result = AI.register(FakePanel, valid_plugin_opts(conversations: false))

      nav_labels = Enum.map(result.nav_items, & &1.label)
      refute "Conversations" in nav_labels
    end

    test "includes cost dashboard nav when enabled" do
      result = AI.register(FakePanel, valid_plugin_opts(cost_dashboard: true))

      nav_labels = Enum.map(result.nav_items, & &1.label)
      assert "Costs" in nav_labels
    end

    test "includes event log nav when enabled" do
      result = AI.register(FakePanel, valid_plugin_opts(event_log: true))

      nav_labels = Enum.map(result.nav_items, & &1.label)
      assert "Event Log" in nav_labels
    end

    test "raises on invalid config" do
      assert_raise NimbleOptions.ValidationError, fn ->
        AI.register(FakePanel, [])
      end
    end
  end

  describe "boot/1" do
    test "assigns :ai_store and :ai_config" do
      # Build a minimal socket-like struct for testing
      config = PhoenixFilamentAI.Config.validate!(valid_plugin_opts())

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          phoenix_filament_ai: config
        }
      }

      result = AI.boot(socket)

      assert result.assigns[:ai_store] == :test_store
      assert result.assigns[:ai_config] == config
    end
  end
end
