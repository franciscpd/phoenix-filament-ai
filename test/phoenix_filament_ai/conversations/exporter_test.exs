defmodule PhoenixFilamentAI.Conversations.ExporterTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Conversations.Exporter

  @conversation %{
    id: "conv-123",
    title: "Test Conversation",
    user_id: "user-1",
    tags: ["dev", "ops"],
    model: "gpt-4o",
    metadata: %{},
    inserted_at: ~U[2026-04-05 10:23:00Z],
    updated_at: ~U[2026-04-05 10:30:00Z],
    message_count: 2,
    total_cost: Decimal.new("0.34"),
    messages: [
      %{
        role: :user,
        content: "Hello",
        token_count: 5,
        inserted_at: ~U[2026-04-05 10:23:00Z],
        tool_calls: nil
      },
      %{
        role: :assistant,
        content: "Hi there!",
        token_count: 12,
        inserted_at: ~U[2026-04-05 10:23:05Z],
        tool_calls: nil
      }
    ]
  }

  # -------------------------------------------------------------------
  # to_json/1
  # -------------------------------------------------------------------

  describe "to_json/1" do
    test "returns valid JSON string" do
      json = Exporter.to_json(@conversation)
      assert is_binary(json)
      assert {:ok, _decoded} = Jason.decode(json)
    end

    test "includes all messages" do
      {:ok, decoded} = Jason.decode(Exporter.to_json(@conversation))
      messages = decoded["messages"]
      assert is_list(messages)
      assert length(messages) == 2
    end

    test "includes conversation metadata" do
      {:ok, decoded} = Jason.decode(Exporter.to_json(@conversation))
      assert decoded["id"] == "conv-123"
      assert decoded["title"] == "Test Conversation"
      assert decoded["user_id"] == "user-1"
      assert decoded["model"] == "gpt-4o"
      assert decoded["tags"] == ["dev", "ops"]
    end

    test "message roles are serialized as strings" do
      {:ok, decoded} = Jason.decode(Exporter.to_json(@conversation))
      roles = Enum.map(decoded["messages"], & &1["role"])
      assert "user" in roles
      assert "assistant" in roles
    end

    test "handles nil content in messages" do
      conv = %{
        @conversation
        | messages: [
            %{
              role: :user,
              content: nil,
              token_count: 0,
              inserted_at: ~U[2026-04-05 10:23:00Z],
              tool_calls: nil
            }
          ]
      }

      json = Exporter.to_json(conv)
      assert {:ok, decoded} = Jason.decode(json)
      assert hd(decoded["messages"])["content"] == nil
    end

    test "handles empty messages list" do
      conv = %{@conversation | messages: []}
      {:ok, decoded} = Jason.decode(Exporter.to_json(conv))
      assert decoded["messages"] == []
    end
  end

  # -------------------------------------------------------------------
  # to_markdown/1
  # -------------------------------------------------------------------

  describe "to_markdown/1" do
    test "includes title as h1 heading" do
      md = Exporter.to_markdown(@conversation)
      assert String.contains?(md, "# Test Conversation")
    end

    test "includes metadata header line" do
      md = Exporter.to_markdown(@conversation)
      assert String.contains?(md, "gpt-4o")
      assert String.contains?(md, "2")
      assert String.contains?(md, "0.34")
    end

    test "includes role labels for each message" do
      md = Exporter.to_markdown(@conversation)
      assert String.contains?(md, "**User**")
      assert String.contains?(md, "**Assistant**")
    end

    test "includes token count for assistant messages" do
      md = Exporter.to_markdown(@conversation)
      assert String.contains?(md, "12 tokens")
    end

    test "includes export footer" do
      md = Exporter.to_markdown(@conversation)
      assert String.contains?(md, "PhoenixFilamentAI")
    end

    test "handles nil content in messages" do
      conv = %{
        @conversation
        | messages: [
            %{
              role: :user,
              content: nil,
              token_count: 0,
              inserted_at: ~U[2026-04-05 10:23:00Z],
              tool_calls: nil
            }
          ]
      }

      md = Exporter.to_markdown(conv)
      assert is_binary(md)
      assert String.contains?(md, "**User**")
    end
  end
end
