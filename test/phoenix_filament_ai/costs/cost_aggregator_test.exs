defmodule PhoenixFilamentAI.Costs.CostAggregatorTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Costs.CostAggregator
  alias PhoenixAI.Store.CostTracking.CostRecord

  defp build_record(attrs) do
    %CostRecord{
      id: attrs[:id] || "rec-#{System.unique_integer([:positive])}",
      conversation_id: attrs[:conversation_id] || "conv-1",
      user_id: attrs[:user_id] || "user-1",
      provider: attrs[:provider] || :openai,
      model: attrs[:model] || "gpt-4o",
      input_tokens: attrs[:input_tokens] || 100,
      output_tokens: attrs[:output_tokens] || 50,
      input_cost: attrs[:input_cost] || Decimal.new("0.001"),
      output_cost: attrs[:output_cost] || Decimal.new("0.002"),
      total_cost: attrs[:total_cost] || Decimal.new("0.003"),
      recorded_at: attrs[:recorded_at] || DateTime.utc_now()
    }
  end

  describe "stats_overview/1" do
    test "computes stats from cost records" do
      records = [
        build_record(%{
          total_cost: Decimal.new("1.50"),
          input_tokens: 1000,
          output_tokens: 500,
          conversation_id: "conv-1"
        }),
        build_record(%{
          total_cost: Decimal.new("2.50"),
          input_tokens: 2000,
          output_tokens: 1000,
          conversation_id: "conv-2"
        })
      ]

      stats = CostAggregator.stats_overview(records)

      assert Decimal.eq?(stats.total_spent, Decimal.new("4.00"))
      assert Decimal.eq?(stats.avg_per_conversation, Decimal.new("2.00"))
      assert stats.total_tokens == 4500
      assert stats.ai_calls == 2
    end

    test "returns zeros for empty records" do
      stats = CostAggregator.stats_overview([])

      assert Decimal.eq?(stats.total_spent, Decimal.new("0"))
      assert Decimal.eq?(stats.avg_per_conversation, Decimal.new("0"))
      assert stats.total_tokens == 0
      assert stats.ai_calls == 0
    end

    test "uses Decimal arithmetic, not floats" do
      records = [
        build_record(%{total_cost: Decimal.new("0.1")}),
        build_record(%{total_cost: Decimal.new("0.2")})
      ]

      stats = CostAggregator.stats_overview(records)

      # 0.1 + 0.2 must equal 0.3 exactly (float would give 0.30000000000000004)
      assert Decimal.eq?(stats.total_spent, Decimal.new("0.3"))
    end
  end

  describe "sparkline_points/2" do
    test "groups records by day for :last_7d period" do
      now = DateTime.utc_now()
      day1 = DateTime.add(now, -6, :day)
      day3 = DateTime.add(now, -4, :day)

      records = [
        build_record(%{
          total_cost: Decimal.new("1.00"),
          recorded_at: day1,
          input_tokens: 100,
          output_tokens: 50
        }),
        build_record(%{
          total_cost: Decimal.new("2.00"),
          recorded_at: day3,
          input_tokens: 200,
          output_tokens: 100
        })
      ]

      sparklines = CostAggregator.sparkline_points(records, :last_7d)

      assert length(sparklines.total_spent) == 7
      assert length(sparklines.calls) == 7
      assert Enum.all?(sparklines.total_spent, &is_struct(&1, Decimal))
    end

    test "returns flat zeros for empty records" do
      sparklines = CostAggregator.sparkline_points([], :last_7d)

      assert length(sparklines.total_spent) == 7
      assert Enum.all?(sparklines.total_spent, &Decimal.eq?(&1, Decimal.new("0")))
    end
  end
end
