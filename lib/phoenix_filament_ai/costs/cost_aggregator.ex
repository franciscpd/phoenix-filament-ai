defmodule PhoenixFilamentAI.Costs.CostAggregator do
  @moduledoc """
  Pure computation module for cost data aggregation.

  All functions are stateless — they receive a list of `CostRecord` structs
  and return aggregated data structures. No Store access, no side-effects.
  All monetary arithmetic uses `Decimal` to satisfy COST-07.
  """

  alias PhoenixAI.Store.CostTracking.CostRecord

  @zero Decimal.new("0")

  # -------------------------------------------------------------------
  # Stats Overview
  # -------------------------------------------------------------------

  @doc """
  Computes overview statistics from cost records.

  Returns total spent, average cost per unique conversation,
  total tokens (input + output), and number of AI calls.
  """
  @spec stats_overview([CostRecord.t()]) :: %{
          total_spent: Decimal.t(),
          avg_per_conversation: Decimal.t(),
          total_tokens: non_neg_integer(),
          ai_calls: non_neg_integer()
        }
  def stats_overview([]) do
    %{total_spent: @zero, avg_per_conversation: @zero, total_tokens: 0, ai_calls: 0}
  end

  def stats_overview(records) do
    total_spent = Enum.reduce(records, @zero, fn r, acc -> Decimal.add(acc, r.total_cost) end)

    unique_conversations =
      records
      |> Enum.map(& &1.conversation_id)
      |> Enum.uniq()
      |> length()

    avg_per_conversation =
      if unique_conversations > 0 do
        Decimal.div(total_spent, Decimal.new(unique_conversations))
      else
        @zero
      end

    total_tokens =
      Enum.reduce(records, 0, fn r, acc ->
        acc + (r.input_tokens || 0) + (r.output_tokens || 0)
      end)

    %{
      total_spent: total_spent,
      avg_per_conversation: avg_per_conversation,
      total_tokens: total_tokens,
      ai_calls: length(records)
    }
  end

  # -------------------------------------------------------------------
  # Sparkline Points
  # -------------------------------------------------------------------

  @doc """
  Generates daily data points for sparkline rendering.

  Returns one value per day for the given period. Days with no records
  get zero values. Used by stat cards for trend visualization.
  """
  @spec sparkline_points([CostRecord.t()], atom()) :: %{
          total_spent: [Decimal.t()],
          avg_cost: [Decimal.t()],
          tokens: [non_neg_integer()],
          calls: [non_neg_integer()]
        }
  def sparkline_points(records, period) do
    days = period_days(period)
    today = Date.utc_today()
    date_range = Date.range(Date.add(today, -(days - 1)), today)

    by_date = group_by_date(records)

    total_spent = Enum.map(date_range, fn d -> sum_field(by_date, d, :total_cost) end)
    tokens = Enum.map(date_range, fn d -> sum_tokens(by_date, d) end)
    calls = Enum.map(date_range, fn d -> count_records(by_date, d) end)

    avg_cost =
      Enum.zip(total_spent, calls)
      |> Enum.map(fn {spent, count} ->
        if count > 0, do: Decimal.div(spent, Decimal.new(count)), else: @zero
      end)

    %{total_spent: total_spent, avg_cost: avg_cost, tokens: tokens, calls: calls}
  end

  # -------------------------------------------------------------------
  # Private — date helpers
  # -------------------------------------------------------------------

  defp period_days(:last_7d), do: 7
  defp period_days(:last_30d), do: 30
  defp period_days(:last_90d), do: 90
  defp period_days(:last_1y), do: 365
  defp period_days(_), do: 7

  defp group_by_date(records) do
    records
    |> Enum.group_by(fn r ->
      case r.recorded_at do
        %DateTime{} = dt -> DateTime.to_date(dt)
        _ -> nil
      end
    end)
    |> Map.delete(nil)
  end

  defp sum_field(by_date, date, field) do
    case Map.get(by_date, date, []) do
      [] -> @zero
      rs -> Enum.reduce(rs, @zero, fn r, acc -> Decimal.add(acc, Map.get(r, field)) end)
    end
  end

  defp sum_tokens(by_date, date) do
    case Map.get(by_date, date, []) do
      [] ->
        0

      rs ->
        Enum.reduce(rs, 0, fn r, acc ->
          acc + (r.input_tokens || 0) + (r.output_tokens || 0)
        end)
    end
  end

  defp count_records(by_date, date) do
    by_date |> Map.get(date, []) |> length()
  end
end
