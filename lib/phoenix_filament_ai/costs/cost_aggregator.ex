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
  # Spending by Period (bar chart data)
  # -------------------------------------------------------------------

  @doc """
  Groups spending by date for bar chart rendering.

  Granularity: `:daily` groups by day, `:weekly` by ISO week, `:monthly` by month.
  Returns a list of `%{date: Date.t(), amount: Decimal.t()}` sorted ascending.
  """
  @spec spending_by_period([CostRecord.t()], atom()) :: [%{date: Date.t(), amount: Decimal.t()}]
  def spending_by_period([], _granularity), do: []

  def spending_by_period(records, granularity) do
    records
    |> Enum.group_by(fn r -> group_key(r.recorded_at, granularity) end)
    |> Map.delete(nil)
    |> Enum.map(fn {date, rs} ->
      %{
        date: date,
        amount: Enum.reduce(rs, @zero, fn r, acc -> Decimal.add(acc, r.total_cost) end)
      }
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  # -------------------------------------------------------------------
  # Distribution by Model (pie chart data)
  # -------------------------------------------------------------------

  @doc """
  Groups spending by model for pie chart rendering.

  Returns a list of `%{label: String.t(), amount: Decimal.t(), percentage: float()}`
  sorted by amount descending. Percentage is the only float — computed for display.
  """
  @spec distribution_by_model([CostRecord.t()]) :: [
          %{label: String.t(), amount: Decimal.t(), percentage: float()}
        ]
  def distribution_by_model([]), do: []

  def distribution_by_model(records) do
    total = Enum.reduce(records, @zero, fn r, acc -> Decimal.add(acc, r.total_cost) end)

    records
    |> Enum.group_by(& &1.model)
    |> Enum.map(fn {model, rs} ->
      amount = Enum.reduce(rs, @zero, fn r, acc -> Decimal.add(acc, r.total_cost) end)

      percentage =
        if Decimal.gt?(total, @zero) do
          amount |> Decimal.div(total) |> Decimal.mult(Decimal.new("100")) |> Decimal.to_float()
        else
          0.0
        end

      %{label: model || "unknown", amount: amount, percentage: percentage}
    end)
    |> Enum.sort_by(fn s -> Decimal.to_float(s.amount) end, :desc)
  end

  # -------------------------------------------------------------------
  # Top Consumers
  # -------------------------------------------------------------------

  @doc """
  Ranks users by total spending, descending.

  Returns `%{user_id, conversations, total_cost, avg_cost, last_activity}`
  limited to the top `limit` users.
  """
  @spec top_consumers([CostRecord.t()], non_neg_integer()) :: [
          %{
            user_id: String.t(),
            conversations: non_neg_integer(),
            total_cost: Decimal.t(),
            avg_cost: Decimal.t(),
            last_activity: DateTime.t() | nil
          }
        ]
  def top_consumers([], _limit), do: []

  def top_consumers(records, limit) do
    records
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, rs} ->
      total_cost = Enum.reduce(rs, @zero, fn r, acc -> Decimal.add(acc, r.total_cost) end)
      conversations = rs |> Enum.map(& &1.conversation_id) |> Enum.uniq() |> length()
      avg_cost = Decimal.div(total_cost, Decimal.new(length(rs)))

      last_activity =
        rs
        |> Enum.map(& &1.recorded_at)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(DateTime, fn -> nil end)

      %{
        user_id: user_id || "unknown",
        conversations: conversations,
        total_cost: total_cost,
        avg_cost: avg_cost,
        last_activity: last_activity
      }
    end)
    |> Enum.sort_by(fn c -> Decimal.to_float(c.total_cost) end, :desc)
    |> Enum.take(limit)
  end

  # -------------------------------------------------------------------
  # compute_all — main entry point
  # -------------------------------------------------------------------

  @doc """
  Computes all aggregated data for the cost dashboard in one call.

  Returns a map with keys: `:stats`, `:sparklines`, `:bar_chart`,
  `:pie_chart`, `:top_consumers`. CostsLive assigns each to a separate
  key for LiveView change tracking.
  """
  @spec compute_all([CostRecord.t()], map()) :: %{
          stats: map(),
          sparklines: map(),
          bar_chart: [map()],
          pie_chart: [map()],
          top_consumers: [map()]
        }
  def compute_all(records, filters) do
    period = Map.get(filters, :period, :last_7d)
    granularity = period_to_granularity(period)

    %{
      stats: stats_overview(records),
      sparklines: sparkline_points(records, period),
      bar_chart: spending_by_period(records, granularity),
      pie_chart: distribution_by_model(records),
      top_consumers: top_consumers(records, 10)
    }
  end

  defp period_to_granularity(:last_7d), do: :daily
  defp period_to_granularity(:last_30d), do: :daily
  defp period_to_granularity(:last_90d), do: :weekly
  defp period_to_granularity(:last_1y), do: :monthly
  defp period_to_granularity(_), do: :daily

  # -------------------------------------------------------------------
  # Private — date helpers
  # -------------------------------------------------------------------

  defp group_key(%DateTime{} = dt, :daily), do: DateTime.to_date(dt)

  defp group_key(%DateTime{} = dt, :weekly) do
    date = DateTime.to_date(dt)
    day_of_week = Date.day_of_week(date)
    Date.add(date, -(day_of_week - 1))
  end

  defp group_key(%DateTime{} = dt, :monthly) do
    date = DateTime.to_date(dt)
    Date.new!(date.year, date.month, 1)
  end

  defp group_key(_, _), do: nil

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
