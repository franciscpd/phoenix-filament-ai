defmodule PhoenixFilamentAI.StoreAdapterTest do
  use ExUnit.Case, async: false

  alias PhoenixFilamentAI.StoreAdapter
  alias PhoenixAI.Store.{Conversation, Message}

  @store_name :test_store_adapter

  setup do
    {:ok, _pid} =
      PhoenixAI.Store.start_link(
        name: @store_name,
        adapter: PhoenixAI.Store.Adapters.ETS
      )

    :ok
  end

  # -------------------------------------------------------------------
  # Conversations
  # -------------------------------------------------------------------

  describe "create_conversation/2" do
    test "creates a conversation with given attributes" do
      attrs = %{title: "Test Chat", user_id: "user-1", model: "gpt-4o"}
      assert {:ok, %Conversation{} = conv} = StoreAdapter.create_conversation(@store_name, attrs)
      assert conv.title == "Test Chat"
      assert conv.user_id == "user-1"
      assert conv.model == "gpt-4o"
      assert conv.id != nil
      assert conv.inserted_at != nil
      assert conv.updated_at != nil
    end

    test "creates a conversation with defaults for optional fields" do
      assert {:ok, %Conversation{} = conv} = StoreAdapter.create_conversation(@store_name, %{})
      assert conv.tags == []
      assert conv.metadata == %{}
      assert conv.title == nil
    end
  end

  describe "get_conversation/2" do
    test "loads a conversation by ID" do
      {:ok, created} = StoreAdapter.create_conversation(@store_name, %{title: "Find Me"})

      assert {:ok, %Conversation{} = found} =
               StoreAdapter.get_conversation(@store_name, created.id)

      assert found.id == created.id
      assert found.title == "Find Me"
    end

    test "returns error for non-existent ID" do
      assert {:error, :not_found} = StoreAdapter.get_conversation(@store_name, "nonexistent-id")
    end
  end

  describe "list_conversations/2" do
    test "lists all conversations" do
      {:ok, _} = StoreAdapter.create_conversation(@store_name, %{title: "Chat 1"})
      {:ok, _} = StoreAdapter.create_conversation(@store_name, %{title: "Chat 2"})

      assert {:ok, convs} = StoreAdapter.list_conversations(@store_name)
      assert length(convs) >= 2
    end

    test "accepts filters" do
      {:ok, _} =
        StoreAdapter.create_conversation(@store_name, %{title: "Filtered", user_id: "filter-user"})

      assert {:ok, convs} = StoreAdapter.list_conversations(@store_name, user_id: "filter-user")
      assert Enum.all?(convs, &(&1.user_id == "filter-user"))
    end
  end

  describe "update_conversation/3" do
    test "updates title on an existing conversation" do
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "Old Title"})

      assert {:ok, updated} =
               StoreAdapter.update_conversation(@store_name, conv.id, %{title: "New Title"})

      assert updated.title == "New Title"
      assert updated.id == conv.id
    end

    test "preserves unchanged fields" do
      {:ok, conv} =
        StoreAdapter.create_conversation(@store_name, %{
          title: "Keep",
          user_id: "user-x",
          model: "gpt-4o"
        })

      {:ok, updated} = StoreAdapter.update_conversation(@store_name, conv.id, %{title: "Changed"})

      assert updated.title == "Changed"
      assert updated.user_id == "user-x"
      assert updated.model == "gpt-4o"
    end

    test "returns error for non-existent conversation" do
      assert {:error, :not_found} =
               StoreAdapter.update_conversation(@store_name, "bad-id", %{title: "Nope"})
    end
  end

  describe "delete_conversation/3" do
    test "deletes an existing conversation" do
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "Delete Me"})
      assert :ok = StoreAdapter.delete_conversation(@store_name, conv.id)
      assert {:error, :not_found} = StoreAdapter.get_conversation(@store_name, conv.id)
    end
  end

  describe "count_conversations/2" do
    test "returns count of conversations" do
      {:ok, _} = StoreAdapter.create_conversation(@store_name, %{title: "Count 1"})
      {:ok, _} = StoreAdapter.create_conversation(@store_name, %{title: "Count 2"})

      assert {:ok, count} = StoreAdapter.count_conversations(@store_name)
      assert is_integer(count)
      assert count >= 2
    end
  end

  # -------------------------------------------------------------------
  # Messages
  # -------------------------------------------------------------------

  describe "list_messages/3" do
    test "returns messages for a conversation with pagination tuple" do
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "With Messages"})

      msg = %Message{role: :user, content: "Hello"}
      {:ok, _} = PhoenixAI.Store.add_message(conv.id, msg, store: @store_name)

      assert {:ok, {messages, next_cursor}} = StoreAdapter.list_messages(@store_name, conv.id)
      assert is_list(messages)
      assert length(messages) >= 1
      assert hd(messages).content == "Hello"
      # With only 1 message and default limit 20, no next cursor
      assert next_cursor == nil
    end

    test "respects limit option" do
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "Many Messages"})

      for i <- 1..5 do
        msg = %Message{role: :user, content: "Message #{i}"}
        {:ok, _} = PhoenixAI.Store.add_message(conv.id, msg, store: @store_name)
      end

      assert {:ok, {messages, next_cursor}} =
               StoreAdapter.list_messages(@store_name, conv.id, limit: 3)

      assert length(messages) == 3
      # We have 5 messages, limit 3 — there should be a cursor
      assert next_cursor != nil
    end

    test "returns empty list for conversation with no messages" do
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "Empty"})

      assert {:ok, {[], nil}} = StoreAdapter.list_messages(@store_name, conv.id)
    end
  end

  # -------------------------------------------------------------------
  # Store info
  # -------------------------------------------------------------------

  describe "backend_type/1" do
    test "returns :ets for ETS-backed store" do
      assert StoreAdapter.backend_type(@store_name) == :ets
    end
  end

  # -------------------------------------------------------------------
  # Conversation stats
  # -------------------------------------------------------------------

  describe "get_conversation_with_stats/2" do
    test "returns conversation with message_count and total_cost" do
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "Stats Test"})
      {:ok, with_stats} = StoreAdapter.get_conversation_with_stats(@store_name, conv.id)

      assert with_stats.id == conv.id
      assert with_stats.title == "Stats Test"
      assert is_integer(with_stats.message_count)
      assert with_stats.message_count >= 0
      assert with_stats.total_cost != nil
      assert with_stats.status == :active
    end

    test "returns error for non-existent conversation" do
      assert {:error, _} = StoreAdapter.get_conversation_with_stats(@store_name, "nonexistent")
    end
  end

  describe "list_conversations_with_stats/1" do
    test "returns list of conversations with stats" do
      {:ok, _} = StoreAdapter.create_conversation(@store_name, %{title: "Stats List 1"})
      result = StoreAdapter.list_conversations_with_stats(@store_name)

      assert is_list(result)
      assert length(result) >= 1
      first = hd(result)
      assert Map.has_key?(first, :message_count)
      assert Map.has_key?(first, :total_cost)
      assert Map.has_key?(first, :status)
    end
  end

  # -------------------------------------------------------------------
  # Converse — skipped in unit tests (requires AI provider)
  # -------------------------------------------------------------------

  # -------------------------------------------------------------------
  # Cost Records
  # -------------------------------------------------------------------

  describe "list_cost_records/2" do
    test "returns cost records matching filters" do
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "Cost Test"})

      record = %PhoenixAI.Store.CostTracking.CostRecord{
        conversation_id: conv.id,
        user_id: "user-1",
        provider: :openai,
        model: "gpt-4o",
        input_tokens: 100,
        output_tokens: 50,
        input_cost: Decimal.new("0.001"),
        output_cost: Decimal.new("0.002"),
        total_cost: Decimal.new("0.003"),
        recorded_at: DateTime.utc_now()
      }

      {:ok, _saved} = save_cost_record(record)

      assert {:ok, %{records: records}} = StoreAdapter.list_cost_records(@store_name)
      assert length(records) >= 1
      assert Enum.any?(records, fn r -> r.conversation_id == conv.id end)
    end

    test "returns empty records when no cost data exists" do
      assert {:ok, %{records: []}} = StoreAdapter.list_cost_records(@store_name)
    end

    test "filters by user_id" do
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "Filter Test"})

      record = %PhoenixAI.Store.CostTracking.CostRecord{
        conversation_id: conv.id,
        user_id: "filter-user",
        provider: :openai,
        model: "gpt-4o",
        input_tokens: 10,
        output_tokens: 5,
        input_cost: Decimal.new("0.001"),
        output_cost: Decimal.new("0.001"),
        total_cost: Decimal.new("0.002"),
        recorded_at: DateTime.utc_now()
      }

      {:ok, _saved} = save_cost_record(record)

      assert {:ok, %{records: records}} =
               StoreAdapter.list_cost_records(@store_name, user_id: "filter-user")

      assert length(records) >= 1
      assert Enum.all?(records, fn r -> r.user_id == "filter-user" end)
    end
  end

  describe "count_cost_records/2" do
    test "counts cost records" do
      assert {:ok, count} = StoreAdapter.count_cost_records(@store_name)
      assert is_integer(count)
    end
  end

  # Saves a cost record directly through the adapter (not exposed via Store facade)
  defp save_cost_record(%PhoenixAI.Store.CostTracking.CostRecord{} = record) do
    config = PhoenixAI.Store.Instance.get_config(@store_name)
    adapter_opts = PhoenixAI.Store.Instance.get_adapter_opts(@store_name)
    config[:adapter].save_cost_record(record, adapter_opts)
  end

  describe "converse/4" do
    @describetag :integration
    test "delegates to PhoenixAI.Store.converse/3" do
      # This test requires a configured AI provider and is skipped
      # in the default test suite. Run with: mix test --include integration
      {:ok, conv} = StoreAdapter.create_conversation(@store_name, %{title: "Converse Test"})

      assert {:ok, _response} =
               StoreAdapter.converse(@store_name, conv.id, "Hello",
                 provider: :test,
                 model: "test"
               )
    end
  end
end
