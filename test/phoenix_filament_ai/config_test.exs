defmodule PhoenixFilamentAI.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Config

  describe "validate!/1" do
    test "accepts valid minimal config (store + provider + model only)" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o"]
      assert {:ok, validated} = Config.validate(opts)
      assert validated[:store] == MyApp.Store
      assert validated[:provider] == :openai
      assert validated[:model] == "gpt-4o"
    end

    test "applies progressive defaults (chat_widget/page true, others false)" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o"]
      {:ok, validated} = Config.validate(opts)

      assert validated[:chat_widget] == true
      assert validated[:chat_page] == true
      assert validated[:conversations] == false
      assert validated[:cost_dashboard] == false
      assert validated[:event_log] == false
    end

    test "raises on missing :store" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Config.validate(provider: :openai, model: "gpt-4o")
    end

    test "raises on missing :provider" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Config.validate(store: MyApp.Store, model: "gpt-4o")
    end

    test "raises on missing :model" do
      assert {:error, %NimbleOptions.ValidationError{}} =
               Config.validate(store: MyApp.Store, provider: :openai)
    end

    test "accepts custom nav_group" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o", nav_group: "Tools"]
      {:ok, validated} = Config.validate(opts)
      assert validated[:nav_group] == "Tools"
    end

    test "default nav_group is AI" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o"]
      {:ok, validated} = Config.validate(opts)
      assert validated[:nav_group] == "AI"
    end

    test "default nav_icon is hero-sparkles" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o"]
      {:ok, validated} = Config.validate(opts)
      assert validated[:nav_icon] == "hero-sparkles"
    end

    test "accepts chat_widget as boolean true" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o", chat_widget: true]
      {:ok, validated} = Config.validate(opts)
      assert validated[:chat_widget] == true
    end

    test "accepts chat_widget as boolean false" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o", chat_widget: false]
      {:ok, validated} = Config.validate(opts)
      assert validated[:chat_widget] == false
    end

    test "accepts chat_widget as keyword list" do
      widget_opts = [column_span: 8, sort: 50, title: "My AI"]

      opts = [
        store: MyApp.Store,
        provider: :openai,
        model: "gpt-4o",
        chat_widget: widget_opts
      ]

      {:ok, validated} = Config.validate(opts)
      assert is_list(validated[:chat_widget])
      assert validated[:chat_widget][:column_span] == 8
      assert validated[:chat_widget][:sort] == 50
      assert validated[:chat_widget][:title] == "My AI"
    end

    test "chat_widget keyword list has defaults" do
      widget_opts = [title: "Custom"]

      opts = [
        store: MyApp.Store,
        provider: :openai,
        model: "gpt-4o",
        chat_widget: widget_opts
      ]

      {:ok, validated} = Config.validate(opts)
      assert validated[:chat_widget][:column_span] == 6
      assert validated[:chat_widget][:sort] == 100
      assert validated[:chat_widget][:max_tokens] == 4096
      assert validated[:chat_widget][:title] == "Custom"
    end

    test "accepts ets_warning option" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o", ets_warning: false]
      {:ok, validated} = Config.validate(opts)
      assert validated[:ets_warning] == false
    end

    test "default ets_warning is true" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o"]
      {:ok, validated} = Config.validate(opts)
      assert validated[:ets_warning] == true
    end

    test "accepts chat options" do
      opts = [
        store: MyApp.Store,
        provider: :openai,
        model: "gpt-4o",
        chat: [system_prompt: "You are helpful.", max_tokens: 2048, temperature: 0.7]
      ]

      {:ok, validated} = Config.validate(opts)
      assert validated[:chat][:system_prompt] == "You are helpful."
      assert validated[:chat][:max_tokens] == 2048
      assert validated[:chat][:temperature] == 0.7
    end

    test "accepts api_key option" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o", api_key: "sk-test"]
      {:ok, validated} = Config.validate(opts)
      assert validated[:api_key] == "sk-test"
    end
  end

  describe "validate!/1 bang version" do
    test "returns validated opts on success" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o"]
      validated = Config.validate!(opts)
      assert validated[:store] == MyApp.Store
    end

    test "raises on invalid config" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Config.validate!(provider: :openai, model: "gpt-4o")
      end
    end
  end

  describe "feature_enabled?/2" do
    test "returns true for enabled features" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o"]
      {:ok, config} = Config.validate(opts)
      assert Config.feature_enabled?(config, :chat_widget) == true
      assert Config.feature_enabled?(config, :chat_page) == true
    end

    test "returns false for disabled features" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o"]
      {:ok, config} = Config.validate(opts)
      assert Config.feature_enabled?(config, :conversations) == false
      assert Config.feature_enabled?(config, :cost_dashboard) == false
      assert Config.feature_enabled?(config, :event_log) == false
    end

    test "returns true for chat_widget as keyword list" do
      opts = [store: MyApp.Store, provider: :openai, model: "gpt-4o", chat_widget: [title: "AI"]]
      {:ok, config} = Config.validate(opts)
      assert Config.feature_enabled?(config, :chat_widget) == true
    end
  end
end
