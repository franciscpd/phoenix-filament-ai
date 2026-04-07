defmodule PhoenixFilamentAI.Costs.CostsLive do
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
    after_dt = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    before_dt = DateTime.new!(to, ~T[23:59:59], "Etc/UTC")
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

  @impl true
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
    bar_chart = Charts.bar_chart_data(assigns.bar_chart_data)
    assigns = assign(assigns, :bar_chart, bar_chart)

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
            class={[
              "pfa-costs-period-btn",
              @filters.period == preset && "pfa-costs-period-btn--active"
            ]}
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
          <span class="pfa-costs-date-separator">to</span>
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
          <%= if @bar_chart do %>
            <Plox.graph for={@bar_chart.graph} id="cost-bar-chart" width={600} height={300}>
              <Plox.y_axis :let={value} scale={@bar_chart.graph[:y]}>
                {format_axis_cost(value)}
              </Plox.y_axis>
              <Plox.x_axis :let={value} scale={@bar_chart.graph[:x]}>
                {format_axis_date(value)}
              </Plox.x_axis>
              <Plox.bar_plot
                dataset={@bar_chart.graph[:spending]}
                x={:x}
                y={:y}
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
                <td class="pfa-costs-td-right pfa-costs-cost">
                  ${format_cost(consumer.total_cost)}
                </td>
                <td class="pfa-costs-td-right">${format_cost(consumer.avg_cost)}</td>
                <td class="pfa-costs-td-right pfa-costs-muted">
                  {format_relative_time(consumer.last_activity)}
                </td>
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

  defp maybe_update_filter(filters, _key, nil), do: filters
  defp maybe_update_filter(filters, _key, ""), do: filters
  defp maybe_update_filter(filters, key, value), do: Map.put(filters, key, value)

  defp maybe_update_date(filters, _key, nil), do: filters
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

  defp available_models(pie_data) do
    Enum.map(pie_data, & &1.label)
  end

  defp format_cost(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()
  defp format_cost(_), do: "0.00"

  defp format_axis_cost(value) when is_number(value) do
    "$#{:erlang.float_to_binary(value / 1, decimals: 2)}"
  end

  defp format_axis_cost(_), do: ""

  defp format_axis_date(%Date{} = d), do: Calendar.strftime(d, "%b %d")
  defp format_axis_date(_), do: ""

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
