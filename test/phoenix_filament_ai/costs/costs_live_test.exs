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
      filters = %{
        period: :last_7d,
        provider: nil,
        model: nil,
        user_id: nil,
        date_from: nil,
        date_to: nil
      }

      store_filters = CostsLive.build_store_filters(filters)

      assert Keyword.has_key?(store_filters, :after)
      refute Keyword.has_key?(store_filters, :provider)
    end

    test "includes provider filter when set" do
      filters = %{
        period: :last_7d,
        provider: "openai",
        model: nil,
        user_id: nil,
        date_from: nil,
        date_to: nil
      }

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
