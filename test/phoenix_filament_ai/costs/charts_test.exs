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
      assert %{graph: %Plox.Graph{}} = result
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

    test "escapes HTML in model labels to prevent XSS" do
      data = [
        %{
          label: ~s[</text><script>alert('xss')</script>],
          amount: Decimal.new("100.00"),
          percentage: 100.0
        }
      ]

      svg = Charts.pie_chart_svg(data)
      refute svg =~ "<script>"
      assert svg =~ "&lt;script&gt;"
    end
  end

  describe "sparkline_svg/2" do
    test "generates SVG polyline from data points" do
      points = [
        Decimal.new("1"),
        Decimal.new("3"),
        Decimal.new("2"),
        Decimal.new("5"),
        Decimal.new("4"),
        Decimal.new("6"),
        Decimal.new("3")
      ]

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
