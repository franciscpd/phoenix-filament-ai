defmodule PhoenixFilamentAI.Costs.Charts do
  @moduledoc """
  Chart rendering boundary module.

  Wraps Plox for bar charts and generates manual SVG for pie charts
  and sparklines. If Plox needs replacement, only this module changes.
  """

  @bar_color "#3b82f6"
  @pie_colors [
    "#3b82f6",
    "#8b5cf6",
    "#f59e0b",
    "#06b6d4",
    "#ef4444",
    "#22c55e",
    "#f97316",
    "#ec4899"
  ]

  # -------------------------------------------------------------------
  # Bar Chart (via Plox)
  # -------------------------------------------------------------------

  @doc """
  Builds Plox graph data for spending-by-period bar chart.

  Returns `nil` if data is empty, or a map with `:graph` and `:dataset_id`
  for use in HEEx templates with `Plox.graph` and `Plox.bar_plot` components.
  """
  @spec bar_chart_data([%{date: Date.t(), amount: Decimal.t()}]) ::
          %{graph: Plox.Graph.t()} | nil
  def bar_chart_data([]), do: nil

  def bar_chart_data(data) do
    float_data =
      Enum.map(data, fn %{date: date, amount: amount} ->
        %{date: date, amount: Decimal.to_float(amount)}
      end)

    dates = Enum.map(float_data, & &1.date)
    amounts = Enum.map(float_data, & &1.amount)
    max_amount = Enum.max(amounts, fn -> 0 end)

    x_scale = Plox.DateScale.new(Date.range(List.first(dates), List.last(dates)))
    y_scale = Plox.NumberScale.new(0, max(max_amount * 1.1, 0.01))

    dataset =
      Plox.Dataset.new(float_data,
        x: {x_scale, & &1.date},
        y: {y_scale, & &1.amount}
      )

    graph =
      Plox.Graph.new(
        scales: [x: x_scale, y: y_scale],
        datasets: [spending: dataset]
      )

    %{graph: graph}
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

        dash_array = "#{Float.round(dash, 2)} #{Float.round(circumference - dash, 2)}"
        dash_offset = Float.round(-offset, 2)

        arc =
          ~s[<circle cx="#{cx}" cy="#{cy}" r="#{radius}" fill="none" ] <>
            ~s[stroke="#{color}" stroke-width="20" ] <>
            ~s[stroke-dasharray="#{dash_array}" ] <>
            ~s[stroke-dashoffset="#{dash_offset}" ] <>
            ~s[transform="rotate(-90 #{cx} #{cy})"/>]

        {arc, offset + dash}
      end)

    legend =
      slices
      |> Enum.with_index()
      |> Enum.map(fn {slice, idx} ->
        color = Enum.at(@pie_colors, rem(idx, length(@pie_colors)))
        y = 15 + idx * 20

        safe_label = escape(slice.label)

        ~s(<rect x="130" y="#{y}" width="10" height="10" rx="2" fill="#{color}"/>) <>
          ~s(<text x="145" y="#{y + 9}" fill="#475569" font-size="11">#{safe_label} — #{Float.round(slice.percentage, 1)}%</text>)
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
  def bar_color, do: @bar_color

  # Escapes HTML special characters for safe SVG text interpolation.
  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp escape(nil), do: "unknown"
  defp escape(other), do: escape(to_string(other))
end
