# Cost Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dedicated cost dashboard page at `/ai/costs` with stats overview, bar chart, pie chart, and top consumers table — all powered by Decimal arithmetic and server-side SVG rendering.

**Architecture:** Hybrid approach — CostsLive loads cost records once via StoreAdapter, CostAggregator pre-computes all widget data as pure functions, separate assigns per widget enable LiveView change tracking. Plox renders bar chart SVG; sparklines and pie chart use manual inline SVG.

**Tech Stack:** Elixir, Phoenix LiveView, Plox (bar chart SVG), PhoenixAI.Store v0.3.0 (`list_cost_records/2`), Decimal arithmetic

---

## File Structure

| File | Responsibility |
|------|----------------|
| `mix.exs` | Add `plox ~> 0.3` runtime dependency |
| `lib/phoenix_filament_ai/store_adapter.ex` | Add `list_cost_records/2` and `count_cost_records/2` |
| `lib/phoenix_filament_ai/costs/cost_aggregator.ex` | Pure functions: stats, sparklines, bar data, pie data, top consumers |
| `lib/phoenix_filament_ai/costs/charts.ex` | Plox wrapper for bar chart + manual SVG for pie chart |
| `lib/phoenix_filament_ai/costs/costs_live.ex` | LiveView orchestrator: mount, filters, render |
| `test/phoenix_filament_ai/store_adapter_test.exs` | Add tests for new cost record functions |
| `test/phoenix_filament_ai/costs/cost_aggregator_test.exs` | Unit tests for all aggregation functions |
| `test/phoenix_filament_ai/costs/charts_test.exs` | Tests for chart SVG generation |
| `test/phoenix_filament_ai/costs/costs_live_test.exs` | LiveView integration tests |

---

### Task 1: Add Plox Dependency and StoreAdapter Extensions

**Files:**
- Modify: `mix.exs:51` (add plox to deps)
- Modify: `lib/phoenix_filament_ai/store_adapter.ex` (add cost record functions)
- Modify: `test/phoenix_filament_ai/store_adapter_test.exs` (add cost record tests)

- [ ] **Step 1: Write failing tests for StoreAdapter cost record functions**

```elixir
# In test/phoenix_filament_ai/store_adapter_test.exs
# Add at the end of the file, before the final `end`

  # -------------------------------------------------------------------
  # Cost Records
  # -------------------------------------------------------------------

  describe "list_cost_records/2" do
    test "returns cost records matching filters" do
      # Create a conversation and record a cost via Store directly
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

      {:ok, _saved} = PhoenixAI.Store.save_cost_record(record, store: @store_name)

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

      {:ok, _saved} = PhoenixAI.Store.save_cost_record(record, store: @store_name)

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_filament_ai/store_adapter_test.exs --only describe:"list_cost_records/2" --only describe:"count_cost_records/2" -v`
Expected: FAIL — `list_cost_records/2` and `count_cost_records/2` not defined

- [ ] **Step 3: Add plox to mix.exs**

In `mix.exs`, add to the deps list after the `{:mdex, "~> 0.12"}` line:

```elixir
      {:plox, "~> 0.3"},
```

- [ ] **Step 4: Add StoreAdapter functions**

In `lib/phoenix_filament_ai/store_adapter.ex`, add before the `# Private helpers` section:

```elixir
  # -------------------------------------------------------------------
  # Cost Records
  # -------------------------------------------------------------------

  @doc """
  Lists cost records matching the given filters.

  Delegates to `PhoenixAI.Store.list_cost_records/2` (v0.3.0+).

  ## Filters

  - `:conversation_id` — filter by conversation
  - `:user_id` — filter by user
  - `:provider` — filter by provider atom
  - `:model` — filter by model string
  - `:after` — records with `recorded_at >= dt`
  - `:before` — records with `recorded_at <= dt`
  - `:cursor` — opaque cursor for pagination
  - `:limit` — max records per page

  Returns `{:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}}`.
  """
  @spec list_cost_records(atom(), keyword()) ::
          {:ok, %{records: [CostRecord.t()], next_cursor: String.t() | nil}} | {:error, term()}
  def list_cost_records(store, filters \\ []) do
    Store.list_cost_records(filters, store: store)
  end

  @doc """
  Counts cost records matching the given filters.

  Delegates to `PhoenixAI.Store.count_cost_records/2` (v0.3.0+).
  Accepts the same filters as `list_cost_records/2` (excluding `:cursor` and `:limit`).
  """
  @spec count_cost_records(atom(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count_cost_records(store, filters \\ []) do
    Store.count_cost_records(filters, store: store)
  end
```

Also add `CostRecord` to the alias at the top of the module:

```elixir
  alias PhoenixAI.Store.CostTracking.CostRecord
```

- [ ] **Step 5: Fetch deps and run tests**

Run: `mix deps.get && mix test test/phoenix_filament_ai/store_adapter_test.exs -v`
Expected: ALL PASS (including new cost record tests)

- [ ] **Step 6: Commit**

```bash
git add mix.exs mix.lock lib/phoenix_filament_ai/store_adapter.ex test/phoenix_filament_ai/store_adapter_test.exs
git commit -m "feat(costs): add plox dep and StoreAdapter cost record functions"
```

---

### Task 2: CostAggregator — stats_overview and sparkline_points

**Files:**
- Create: `lib/phoenix_filament_ai/costs/cost_aggregator.ex`
- Create: `test/phoenix_filament_ai/costs/cost_aggregator_test.exs`

- [ ] **Step 1: Write failing tests for stats_overview**

```elixir
# test/phoenix_filament_ai/costs/cost_aggregator_test.exs
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
        build_record(%{total_cost: Decimal.new("1.00"), recorded_at: day1, input_tokens: 100, output_tokens: 50}),
        build_record(%{total_cost: Decimal.new("2.00"), recorded_at: day3, input_tokens: 200, output_tokens: 100})
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_filament_ai/costs/cost_aggregator_test.exs -v`
Expected: FAIL — module not found

- [ ] **Step 3: Implement CostAggregator with stats_overview and sparkline_points**

```elixir
# lib/phoenix_filament_ai/costs/cost_aggregator.ex
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
    Enum.group_by(records, fn r ->
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
      [] -> 0
      rs -> Enum.reduce(rs, 0, fn r, acc -> acc + (r.input_tokens || 0) + (r.output_tokens || 0) end)
    end
  end

  defp count_records(by_date, date) do
    by_date |> Map.get(date, []) |> length()
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_filament_ai/costs/cost_aggregator_test.exs -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/costs/cost_aggregator.ex test/phoenix_filament_ai/costs/cost_aggregator_test.exs
git commit -m "feat(costs): add CostAggregator with stats_overview and sparkline_points"
```

---

### Task 3: CostAggregator — spending_by_period, distribution_by_model, top_consumers

**Files:**
- Modify: `lib/phoenix_filament_ai/costs/cost_aggregator.ex`
- Modify: `test/phoenix_filament_ai/costs/cost_aggregator_test.exs`

- [ ] **Step 1: Write failing tests**

Add to `test/phoenix_filament_ai/costs/cost_aggregator_test.exs`:

```elixir
  describe "spending_by_period/2" do
    test "groups spending by day for :daily granularity" do
      now = DateTime.utc_now()
      yesterday = DateTime.add(now, -1, :day)

      records = [
        build_record(%{total_cost: Decimal.new("1.00"), recorded_at: now}),
        build_record(%{total_cost: Decimal.new("2.00"), recorded_at: now}),
        build_record(%{total_cost: Decimal.new("3.00"), recorded_at: yesterday})
      ]

      result = CostAggregator.spending_by_period(records, :daily)

      assert is_list(result)
      assert Enum.all?(result, fn item -> is_struct(item.amount, Decimal) end)
      assert Enum.all?(result, fn item -> is_struct(item.date, Date) end)

      today_entry = Enum.find(result, fn item -> item.date == Date.utc_today() end)
      assert Decimal.eq?(today_entry.amount, Decimal.new("3.00"))
    end

    test "returns empty list for no records" do
      assert CostAggregator.spending_by_period([], :daily) == []
    end
  end

  describe "distribution_by_model/1" do
    test "groups and calculates percentage by model" do
      records = [
        build_record(%{model: "gpt-4o", total_cost: Decimal.new("3.00")}),
        build_record(%{model: "gpt-4o", total_cost: Decimal.new("2.00")}),
        build_record(%{model: "claude-3.5", total_cost: Decimal.new("5.00")})
      ]

      result = CostAggregator.distribution_by_model(records)

      assert length(result) == 2

      gpt = Enum.find(result, fn s -> s.label == "gpt-4o" end)
      assert Decimal.eq?(gpt.amount, Decimal.new("5.00"))
      assert_in_delta gpt.percentage, 50.0, 0.01

      claude = Enum.find(result, fn s -> s.label == "claude-3.5" end)
      assert Decimal.eq?(claude.amount, Decimal.new("5.00"))
      assert_in_delta claude.percentage, 50.0, 0.01
    end

    test "returns empty list for no records" do
      assert CostAggregator.distribution_by_model([]) == []
    end
  end

  describe "top_consumers/2" do
    test "ranks users by total cost descending" do
      records = [
        build_record(%{user_id: "alice", conversation_id: "c1", total_cost: Decimal.new("5.00")}),
        build_record(%{user_id: "alice", conversation_id: "c2", total_cost: Decimal.new("3.00")}),
        build_record(%{user_id: "bob", conversation_id: "c3", total_cost: Decimal.new("10.00")})
      ]

      result = CostAggregator.top_consumers(records, 10)

      assert length(result) == 2
      [first | _] = result
      assert first.user_id == "bob"
      assert Decimal.eq?(first.total_cost, Decimal.new("10.00"))
      assert first.conversations == 1
    end

    test "limits results to N" do
      records = [
        build_record(%{user_id: "a", total_cost: Decimal.new("1.00")}),
        build_record(%{user_id: "b", total_cost: Decimal.new("2.00")}),
        build_record(%{user_id: "c", total_cost: Decimal.new("3.00")})
      ]

      result = CostAggregator.top_consumers(records, 2)
      assert length(result) == 2
    end

    test "returns empty list for no records" do
      assert CostAggregator.top_consumers([], 10) == []
    end
  end

  describe "compute_all/2" do
    test "returns all aggregated data in one call" do
      records = [
        build_record(%{
          total_cost: Decimal.new("5.00"),
          model: "gpt-4o",
          user_id: "alice",
          conversation_id: "c1",
          recorded_at: DateTime.utc_now()
        })
      ]

      result = CostAggregator.compute_all(records, %{period: :last_7d})

      assert Map.has_key?(result, :stats)
      assert Map.has_key?(result, :sparklines)
      assert Map.has_key?(result, :bar_chart)
      assert Map.has_key?(result, :pie_chart)
      assert Map.has_key?(result, :top_consumers)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_filament_ai/costs/cost_aggregator_test.exs -v`
Expected: FAIL — functions not defined

- [ ] **Step 3: Implement remaining CostAggregator functions**

Add to `lib/phoenix_filament_ai/costs/cost_aggregator.ex`, after the sparkline section:

```elixir
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
      %{date: date, amount: Enum.reduce(rs, @zero, fn r, acc -> Decimal.add(acc, r.total_cost) end)}
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  defp group_key(%DateTime{} = dt, :daily), do: DateTime.to_date(dt)

  defp group_key(%DateTime{} = dt, :weekly) do
    date = DateTime.to_date(dt)
    # Start of ISO week (Monday)
    day_of_week = Date.day_of_week(date)
    Date.add(date, -(day_of_week - 1))
  end

  defp group_key(%DateTime{} = dt, :monthly) do
    date = DateTime.to_date(dt)
    Date.new!(date.year, date.month, 1)
  end

  defp group_key(_, _), do: nil

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_filament_ai/costs/cost_aggregator_test.exs -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/costs/cost_aggregator.ex test/phoenix_filament_ai/costs/cost_aggregator_test.exs
git commit -m "feat(costs): add spending_by_period, distribution_by_model, top_consumers, compute_all"
```

---

### Task 4: Charts Module — Bar Chart (Plox) + Pie Chart (Manual SVG)

**Files:**
- Create: `lib/phoenix_filament_ai/costs/charts.ex`
- Create: `test/phoenix_filament_ai/costs/charts_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# test/phoenix_filament_ai/costs/charts_test.exs
defmodule PhoenixFilamentAI.Costs.ChartsTest do
  use ExUnit.Case, async: true

  alias PhoenixFilamentAI.Costs.Charts

  describe "bar_chart_data/1" do
    test "returns a map with Plox.Graph struct from bar data" do
      data = [
        %{date: ~D[2026-04-01], amount: Decimal.new("10.50")},
        %{date: ~D[2026-04-02], amount: Decimal.new("20.00")},
        %{date: ~D[2026-04-03], amount: Decimal.new("5.75")}
      ]

      result = Charts.bar_chart_data(data)
      assert %{graph: %Plox.Graph{}, x_scale: _, y_scale: _, dataset: _} = result
    end

    test "handles empty data" do
      assert Charts.bar_chart_data([]) == nil
    end
  end

  describe "pie_chart_svg/1" do
    test "returns SVG markup for pie slices" do
      data = [
        %{label: "gpt-4o", amount: Decimal.new("60.00"), percentage: 60.0},
        %{label: "claude-3.5", amount: Decimal.new("40.00"), percentage: 40.0}
      ]

      svg = Charts.pie_chart_svg(data)
      assert is_binary(svg)
      assert svg =~ "<svg"
      assert svg =~ "gpt-4o"
      assert svg =~ "claude-3.5"
    end

    test "returns empty message for no data" do
      svg = Charts.pie_chart_svg([])
      assert svg =~ "No data"
    end
  end

  describe "sparkline_svg/2" do
    test "generates SVG polyline from data points" do
      points = [Decimal.new("1"), Decimal.new("3"), Decimal.new("2"), Decimal.new("5"), Decimal.new("4"), Decimal.new("6"), Decimal.new("3")]

      svg = Charts.sparkline_svg(points, "#3b82f6")
      assert is_binary(svg)
      assert svg =~ "<svg"
      assert svg =~ "polyline"
      assert svg =~ "#3b82f6"
    end

    test "handles all-zero data" do
      points = List.duplicate(Decimal.new("0"), 7)
      svg = Charts.sparkline_svg(points, "#3b82f6")
      assert svg =~ "<svg"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_filament_ai/costs/charts_test.exs -v`
Expected: FAIL — module not found

- [ ] **Step 3: Implement Charts module**

```elixir
# lib/phoenix_filament_ai/costs/charts.ex
defmodule PhoenixFilamentAI.Costs.Charts do
  @moduledoc """
  Chart rendering boundary module.

  Wraps Plox for bar charts and generates manual SVG for pie charts
  and sparklines. If Plox needs replacement, only this module changes.
  """

  @bar_colors ["#3b82f6"]
  @pie_colors ["#3b82f6", "#8b5cf6", "#f59e0b", "#06b6d4", "#ef4444", "#22c55e", "#f97316", "#ec4899"]

  # -------------------------------------------------------------------
  # Bar Chart (via Plox)
  # -------------------------------------------------------------------

  @doc """
  Builds Plox graph data for spending-by-period bar chart.

  Returns `nil` if data is empty, or a map with `:graph`, `:x_scale`,
  `:y_scale`, and `:dataset` for use in HEEx templates.
  """
  @spec bar_chart_data([%{date: Date.t(), amount: Decimal.t()}]) ::
          %{graph: Plox.Graph.t(), x_scale: term(), y_scale: term(), dataset: term()} | nil
  def bar_chart_data([]), do: nil

  def bar_chart_data(data) do
    float_data =
      Enum.map(data, fn %{date: date, amount: amount} ->
        %{date: date, amount: Decimal.to_float(amount)}
      end)

    dates = Enum.map(float_data, & &1.date)
    amounts = Enum.map(float_data, & &1.amount)
    max_amount = Enum.max(amounts, fn -> 0 end)

    x_scale = Plox.date_scale(Date.range(List.first(dates), List.last(dates)))
    y_scale = Plox.number_scale(0, max_amount * 1.1)
    dataset = Plox.dataset(float_data, x: :date, y: :amount)

    graph =
      Plox.to_graph(
        x_scale: x_scale,
        y_scale: y_scale,
        dataset: dataset
      )

    %{graph: graph, x_scale: x_scale, y_scale: y_scale, dataset: dataset}
  end

  # -------------------------------------------------------------------
  # Pie Chart (manual SVG)
  # -------------------------------------------------------------------

  @doc """
  Generates an SVG string for a donut-style pie chart.

  Each slice is an SVG `<circle>` with `stroke-dasharray` and
  `stroke-dashoffset` to create arc segments.
  """
  @spec pie_chart_svg([%{label: String.t(), amount: Decimal.t(), percentage: float()}]) ::
          String.t()
  def pie_chart_svg([]) do
    ~s(<svg viewBox="0 0 200 120" xmlns="http://www.w3.org/2000/svg"><text x="100" y="60" text-anchor="middle" fill="#94a3b8" font-size="14">No data for selected period</text></svg>)
  end

  def pie_chart_svg(slices) do
    radius = 40
    circumference = 2 * :math.pi() * radius
    cx = 60
    cy = 60

    {arcs, _offset} =
      slices
      |> Enum.with_index()
      |> Enum.map_reduce(0.0, fn {slice, idx}, offset ->
        dash = circumference * slice.percentage / 100.0
        color = Enum.at(@pie_colors, rem(idx, length(@pie_colors)))

        arc =
          ~s(<circle cx="#{cx}" cy="#{cy}" r="#{radius}" fill="none" stroke="#{color}" stroke-width="20" stroke-dasharray="#{Float.round(dash, 2)} #{Float.round(circumference - dash, 2)}" stroke-dashoffset="#{Float.round(-offset, 2)}" transform="rotate(-90 #{cx} #{cy})"/>)

        {arc, offset + dash}
      end)

    legend =
      slices
      |> Enum.with_index()
      |> Enum.map(fn {slice, idx} ->
        color = Enum.at(@pie_colors, rem(idx, length(@pie_colors)))
        y = 15 + idx * 20

        ~s(<rect x="130" y="#{y}" width="10" height="10" rx="2" fill="#{color}"/>) <>
          ~s(<text x="145" y="#{y + 9}" fill="#475569" font-size="11">#{slice.label} — #{Float.round(slice.percentage, 1)}%</text>)
      end)

    height = max(120, 15 + length(slices) * 20 + 10)

    ~s(<svg viewBox="0 0 300 #{height}" xmlns="http://www.w3.org/2000/svg">) <>
      Enum.join(arcs) <>
      Enum.join(legend) <>
      ~s(</svg>)
  end

  # -------------------------------------------------------------------
  # Sparkline (manual SVG)
  # -------------------------------------------------------------------

  @doc """
  Generates a compact SVG sparkline from a list of Decimal values.

  Returns an SVG string with a single `<polyline>` element.
  Width: 80px, Height: 32px.
  """
  @spec sparkline_svg([Decimal.t()], String.t()) :: String.t()
  def sparkline_svg(points, color) do
    float_points = Enum.map(points, &Decimal.to_float/1)
    max_val = Enum.max(float_points, fn -> 1 end)
    min_val = Enum.min(float_points, fn -> 0 end)
    range = if max_val == min_val, do: 1.0, else: max_val - min_val

    width = 80
    height = 32
    padding = 2
    usable_h = height - padding * 2
    usable_w = width - padding * 2

    count = length(float_points)
    step = if count > 1, do: usable_w / (count - 1), else: 0

    coords =
      float_points
      |> Enum.with_index()
      |> Enum.map(fn {val, idx} ->
        x = Float.round(padding + idx * step, 1)
        y = Float.round(padding + usable_h - (val - min_val) / range * usable_h, 1)
        "#{x},#{y}"
      end)
      |> Enum.join(" ")

    ~s(<svg viewBox="0 0 #{width} #{height}" xmlns="http://www.w3.org/2000/svg">) <>
      ~s(<polyline points="#{coords}" fill="none" stroke="#{color}" stroke-width="2" stroke-linecap="round"/>) <>
      ~s(</svg>)
  end

  @doc "Returns the default bar chart color."
  def bar_color, do: List.first(@bar_colors)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_filament_ai/costs/charts_test.exs -v`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_filament_ai/costs/charts.ex test/phoenix_filament_ai/costs/charts_test.exs
git commit -m "feat(costs): add Charts module with Plox bar chart, SVG pie chart and sparkline"
```

---

### Task 5: CostsLive — LiveView with Filters and Data Loading

**Files:**
- Create: `lib/phoenix_filament_ai/costs/costs_live.ex`
- Create: `test/phoenix_filament_ai/costs/costs_live_test.exs`

- [ ] **Step 1: Write failing tests for CostsLive**

```elixir
# test/phoenix_filament_ai/costs/costs_live_test.exs
defmodule PhoenixFilamentAI.Costs.CostsLiveTest do
  use ExUnit.Case, async: false

  alias PhoenixFilamentAI.Costs.CostsLive

  describe "default_filters/0" do
    test "returns default filter map" do
      filters = CostsLive.default_filters()
      assert filters.period == :last_7d
      assert filters.provider == nil
      assert filters.model == nil
      assert filters.user_id == nil
      assert filters.date_from == nil
      assert filters.date_to == nil
    end
  end

  describe "build_store_filters/1" do
    test "converts period to :after/:before Store filters" do
      filters = %{period: :last_7d, provider: nil, model: nil, user_id: nil, date_from: nil, date_to: nil}
      store_filters = CostsLive.build_store_filters(filters)

      assert Keyword.has_key?(store_filters, :after)
      refute Keyword.has_key?(store_filters, :provider)
    end

    test "includes provider filter when set" do
      filters = %{period: :last_7d, provider: "openai", model: nil, user_id: nil, date_from: nil, date_to: nil}
      store_filters = CostsLive.build_store_filters(filters)

      assert Keyword.get(store_filters, :provider) == :openai
    end

    test "uses custom date range when date_from and date_to are set" do
      filters = %{
        period: :custom,
        provider: nil,
        model: nil,
        user_id: nil,
        date_from: ~D[2026-03-01],
        date_to: ~D[2026-03-15]
      }

      store_filters = CostsLive.build_store_filters(filters)

      assert %DateTime{} = Keyword.get(store_filters, :after)
      assert %DateTime{} = Keyword.get(store_filters, :before)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/phoenix_filament_ai/costs/costs_live_test.exs -v`
Expected: FAIL — module not found

- [ ] **Step 3: Implement CostsLive**

```elixir
# lib/phoenix_filament_ai/costs/costs_live.ex
defmodule PhoenixFilamentAI.CostsLive do
  @moduledoc """
  LiveView for the cost dashboard page at `/ai/costs`.

  Loads cost records via StoreAdapter, aggregates via CostAggregator,
  and renders stats cards, charts, and top consumers table as function
  components. Global filter bar at the top affects all widgets.

  ## Assigns

  - `:filters` — current filter state (period, provider, model, user_id, dates)
  - `:stats` — stats overview map (total_spent, avg_per_conversation, etc.)
  - `:sparkline_data` — sparkline points per stat card
  - `:bar_chart_data` — spending by period for bar chart
  - `:pie_chart_data` — distribution by model for pie chart
  - `:top_consumers` — ranked list of top spending users
  - `:config` — plugin config
  - `:store` — store atom
  """

  use Phoenix.LiveView

  alias PhoenixFilamentAI.Costs.{CostAggregator, Charts}
  alias PhoenixFilamentAI.StoreAdapter

  require Logger

  @period_presets ~w(last_7d last_30d last_90d last_1y)a

  # -------------------------------------------------------------------
  # Public — filter helpers (tested directly)
  # -------------------------------------------------------------------

  @doc false
  def default_filters do
    %{
      period: :last_7d,
      provider: nil,
      model: nil,
      user_id: nil,
      date_from: nil,
      date_to: nil
    }
  end

  @doc false
  def build_store_filters(filters) do
    []
    |> maybe_add_period(filters)
    |> maybe_add_filter(:provider, filters.provider, &String.to_existing_atom/1)
    |> maybe_add_filter(:model, filters.model, & &1)
    |> maybe_add_filter(:user_id, filters.user_id, & &1)
  end

  defp maybe_add_period(acc, %{period: :custom, date_from: from, date_to: to})
       when not is_nil(from) and not is_nil(to) do
    after_dt = from |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    before_dt = to |> DateTime.new!(~T[23:59:59], "Etc/UTC")
    Keyword.merge(acc, after: after_dt, before: before_dt)
  end

  defp maybe_add_period(acc, %{period: period}) do
    days = period_days(period)
    after_dt = DateTime.utc_now() |> DateTime.add(-days, :day)
    Keyword.put(acc, :after, after_dt)
  end

  defp maybe_add_filter(acc, _key, nil, _transform), do: acc
  defp maybe_add_filter(acc, _key, "", _transform), do: acc
  defp maybe_add_filter(acc, key, value, transform), do: Keyword.put(acc, key, transform.(value))

  defp period_days(:last_7d), do: 7
  defp period_days(:last_30d), do: 30
  defp period_days(:last_90d), do: 90
  defp period_days(:last_1y), do: 365
  defp period_days(_), do: 7

  # -------------------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    config = socket.assigns[:ai_config] || default_config()
    store = config[:store]

    {:ok,
     socket
     |> assign(:config, config)
     |> assign(:store, store)
     |> assign(:filters, default_filters())
     |> assign(:stats, CostAggregator.stats_overview([]))
     |> assign(:sparkline_data, CostAggregator.sparkline_points([], :last_7d))
     |> assign(:bar_chart_data, [])
     |> assign(:pie_chart_data, [])
     |> assign(:top_consumers, [])
     |> assign(:page_title, "Costs")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, load_and_aggregate(socket)}
  end

  # -------------------------------------------------------------------
  # Events
  # -------------------------------------------------------------------

  @impl true
  def handle_event("select_period", %{"period" => period}, socket) do
    period_atom = String.to_existing_atom(period)

    filters =
      socket.assigns.filters
      |> Map.put(:period, period_atom)
      |> Map.put(:date_from, nil)
      |> Map.put(:date_to, nil)

    socket =
      socket
      |> assign(:filters, filters)
      |> load_and_aggregate()

    {:noreply, socket}
  end

  def handle_event("filter_changed", params, socket) do
    filters =
      socket.assigns.filters
      |> maybe_update_filter(:provider, params["provider"])
      |> maybe_update_filter(:model, params["model"])
      |> maybe_update_filter(:user_id, params["user_id"])
      |> maybe_update_date(:date_from, params["date_from"])
      |> maybe_update_date(:date_to, params["date_to"])

    filters =
      if filters.date_from && filters.date_to do
        Map.put(filters, :period, :custom)
      else
        filters
      end

    socket =
      socket
      |> assign(:filters, filters)
      |> load_and_aggregate()

    {:noreply, socket}
  end

  # -------------------------------------------------------------------
  # Render
  # -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pfa-costs-page">
      <div class="pfa-costs-header">
        <h1 class="pfa-costs-title">Costs</h1>
      </div>

      <%!-- Filter Bar --%>
      <div class="pfa-costs-filters">
        <div class="pfa-costs-period-presets">
          <button
            :for={preset <- period_presets()}
            phx-click="select_period"
            phx-value-period={preset}
            class={"pfa-costs-period-btn #{if @filters.period == preset, do: "pfa-costs-period-btn--active", else: ""}"}
          >
            {period_label(preset)}
          </button>
        </div>

        <div class="pfa-costs-date-range">
          <input
            type="date"
            name="date_from"
            value={@filters.date_from}
            phx-change="filter_changed"
            class="pfa-costs-date-input"
          />
          <span class="pfa-costs-date-separator">→</span>
          <input
            type="date"
            name="date_to"
            value={@filters.date_to}
            phx-change="filter_changed"
            class="pfa-costs-date-input"
          />
        </div>

        <div class="pfa-costs-dropdowns">
          <select name="provider" phx-change="filter_changed" class="pfa-costs-select">
            <option value="">All Providers</option>
            <option :for={p <- available_providers(@top_consumers)} value={p}>{p}</option>
          </select>
          <select name="model" phx-change="filter_changed" class="pfa-costs-select">
            <option value="">All Models</option>
            <option :for={m <- available_models(@pie_chart_data)} value={m}>{m}</option>
          </select>
        </div>
      </div>

      <%!-- Stats Cards --%>
      <div class="pfa-costs-stats-grid">
        <.stat_card
          label="Total Spent"
          value={"$#{format_cost(@stats.total_spent)}"}
          sparkline_points={@sparkline_data.total_spent}
          color="#3b82f6"
        />
        <.stat_card
          label="Avg / Conversation"
          value={"$#{format_cost(@stats.avg_per_conversation)}"}
          sparkline_points={@sparkline_data.avg_cost}
          color="#f59e0b"
        />
        <.stat_card
          label="Total Tokens"
          value={format_number(@stats.total_tokens)}
          sparkline_points={Enum.map(@sparkline_data.tokens, &Decimal.new/1)}
          color="#8b5cf6"
        />
        <.stat_card
          label="AI Calls"
          value={format_number(@stats.ai_calls)}
          sparkline_points={Enum.map(@sparkline_data.calls, &Decimal.new/1)}
          color="#06b6d4"
        />
      </div>

      <%!-- Charts Row --%>
      <div class="pfa-costs-charts-row">
        <div class="pfa-costs-bar-chart">
          <h3 class="pfa-costs-section-title">Spending by Period</h3>
          <%= if bar = Charts.bar_chart_data(@bar_chart_data) do %>
            <Plox.graph for={bar.graph} id="cost-bar-chart" width={600} height={300}>
              <Plox.y_axis scale={bar.y_scale} />
              <Plox.x_axis scale={bar.x_scale} />
              <Plox.bar_plot
                dataset={bar.dataset}
                x={:date}
                y={:amount}
                color={Charts.bar_color()}
              />
            </Plox.graph>
          <% else %>
            <div class="pfa-costs-empty">No data for selected period</div>
          <% end %>
        </div>

        <div class="pfa-costs-pie-chart">
          <h3 class="pfa-costs-section-title">Distribution by Model</h3>
          {Phoenix.HTML.raw(Charts.pie_chart_svg(@pie_chart_data))}
        </div>
      </div>

      <%!-- Top Consumers Table --%>
      <div class="pfa-costs-table-section">
        <h3 class="pfa-costs-section-title">
          Top Consumers
          <span class="pfa-costs-section-subtitle">by total spending</span>
        </h3>
        <table class="pfa-costs-table">
          <thead>
            <tr>
              <th>#</th>
              <th>User</th>
              <th class="pfa-costs-th-right">Conversations</th>
              <th class="pfa-costs-th-right">Total Cost</th>
              <th class="pfa-costs-th-right">Avg Cost</th>
              <th class="pfa-costs-th-right">Last Activity</th>
            </tr>
          </thead>
          <tbody>
            <%= if Enum.empty?(@top_consumers) do %>
              <tr>
                <td colspan="6" class="pfa-costs-empty-row">No cost records found</td>
              </tr>
            <% else %>
              <tr :for={{consumer, idx} <- Enum.with_index(@top_consumers, 1)}>
                <td class="pfa-costs-rank">{idx}</td>
                <td class="pfa-costs-user">{consumer.user_id}</td>
                <td class="pfa-costs-td-right">{consumer.conversations}</td>
                <td class="pfa-costs-td-right pfa-costs-cost">${format_cost(consumer.total_cost)}</td>
                <td class="pfa-costs-td-right">${format_cost(consumer.avg_cost)}</td>
                <td class="pfa-costs-td-right pfa-costs-muted">{format_relative_time(consumer.last_activity)}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Function component — stat card
  # -------------------------------------------------------------------

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sparkline_points, :list, required: true
  attr :color, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="pfa-costs-stat-card">
      <div class="pfa-costs-stat-content">
        <div class="pfa-costs-stat-label">{@label}</div>
        <div class="pfa-costs-stat-value">{@value}</div>
      </div>
      <div class="pfa-costs-stat-sparkline">
        {Phoenix.HTML.raw(Charts.sparkline_svg(@sparkline_points, @color))}
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Private — data loading
  # -------------------------------------------------------------------

  defp load_and_aggregate(socket) do
    store = socket.assigns.store

    if is_nil(store) do
      socket
    else
      filters = build_store_filters(socket.assigns.filters)

      case StoreAdapter.list_cost_records(store, filters) do
        {:ok, %{records: records}} ->
          aggregated = CostAggregator.compute_all(records, socket.assigns.filters)

          socket
          |> assign(:stats, aggregated.stats)
          |> assign(:sparkline_data, aggregated.sparklines)
          |> assign(:bar_chart_data, aggregated.bar_chart)
          |> assign(:pie_chart_data, aggregated.pie_chart)
          |> assign(:top_consumers, aggregated.top_consumers)

        {:error, reason} ->
          Logger.error("Failed to load cost records: #{inspect(reason)}")
          put_flash(socket, :error, "Failed to load cost data")
      end
    end
  end

  # -------------------------------------------------------------------
  # Private — helpers
  # -------------------------------------------------------------------

  defp maybe_update_filter(filters, key, nil), do: filters
  defp maybe_update_filter(filters, key, ""), do: Map.put(filters, key, nil)
  defp maybe_update_filter(filters, key, value), do: Map.put(filters, key, value)

  defp maybe_update_date(filters, key, nil), do: filters
  defp maybe_update_date(filters, key, ""), do: Map.put(filters, key, nil)

  defp maybe_update_date(filters, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(filters, key, date)
      _ -> filters
    end
  end

  defp period_presets, do: @period_presets

  defp period_label(:last_7d), do: "7d"
  defp period_label(:last_30d), do: "30d"
  defp period_label(:last_90d), do: "90d"
  defp period_label(:last_1y), do: "1y"
  defp period_label(_), do: "?"

  defp available_providers(top_consumers) do
    top_consumers |> Enum.map(& &1.user_id) |> Enum.uniq()
  end

  defp available_models(pie_data) do
    Enum.map(pie_data, & &1.label)
  end

  defp format_cost(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()
  defp format_cost(_), do: "0.00"

  defp format_number(n) when is_integer(n) do
    cond do
      n >= 1_000_000 -> "#{Float.round(n / 1_000_000, 1)}M"
      n >= 1_000 -> "#{Float.round(n / 1_000, 1)}K"
      true -> Integer.to_string(n)
    end
  end

  defp format_number(_), do: "0"

  defp format_relative_time(nil), do: "—"

  defp format_relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      true -> Calendar.strftime(dt, "%b %d, %Y")
    end
  end

  defp format_relative_time(_), do: "—"

  defp default_config do
    [store: nil, provider: nil, model: nil, chat: []]
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/phoenix_filament_ai/costs/costs_live_test.exs -v`
Expected: ALL PASS

- [ ] **Step 5: Run full test suite**

Run: `mix test -v`
Expected: ALL PASS — no regressions

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_filament_ai/costs/costs_live.ex test/phoenix_filament_ai/costs/costs_live_test.exs
git commit -m "feat(costs): add CostsLive with filters, stats cards, charts, and top consumers"
```

---

### Task 6: Update phoenix_ai_store version constraint in mix.exs

**Files:**
- Modify: `mix.exs:51`

- [ ] **Step 1: Update version constraint**

In `mix.exs`, change the phoenix_ai_store line:

```elixir
# From:
{:phoenix_ai_store, "~> 0.1"},
# To:
{:phoenix_ai_store, "~> 0.3"},
```

- [ ] **Step 2: Run deps.get and tests**

Run: `mix deps.get && mix test -v`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add mix.exs mix.lock
git commit -m "chore(deps): update phoenix_ai_store to ~> 0.3 for cost record API"
```

---

### Task 7: Final Integration Verification

**Files:** None — verification only

- [ ] **Step 1: Run full test suite**

Run: `mix test -v`
Expected: ALL PASS

- [ ] **Step 2: Run linting**

Run: `mix format --check-formatted && mix credo --strict`
Expected: No warnings or errors

- [ ] **Step 3: Verify compilation is clean**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation, no warnings

- [ ] **Step 4: Commit any format/lint fixes if needed**

```bash
mix format
git add -A
git commit -m "style(costs): apply formatting"
```

---

## Requirements Coverage

| Requirement | Task |
|-------------|------|
| COST-01: Stats overview widget | Task 2 (aggregator) + Task 5 (stat cards in CostsLive) |
| COST-02: Trend sparklines | Task 2 (sparkline_points) + Task 4 (sparkline_svg) + Task 5 (stat_card component) |
| COST-03: Bar chart by period | Task 3 (spending_by_period) + Task 4 (bar_chart_graph) + Task 5 (Plox render in CostsLive) |
| COST-04: Pie chart by model | Task 3 (distribution_by_model) + Task 4 (pie_chart_svg) + Task 5 (render in CostsLive) |
| COST-05: Charts support filters | Task 5 (global filter bar, handle_event filter_changed) |
| COST-06: Top consumers table | Task 3 (top_consumers) + Task 5 (table render in CostsLive) |
| COST-07: Decimal arithmetic | Task 2+3 (all CostAggregator uses Decimal) + Task 4 (float only at SVG render) |
