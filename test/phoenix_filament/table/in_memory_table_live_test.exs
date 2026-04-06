defmodule PhoenixFilament.Table.InMemoryTableLiveTest do
  use ExUnit.Case, async: true

  alias PhoenixFilament.Column
  alias PhoenixFilament.Table.Filter
  alias PhoenixFilament.Table.InMemoryTableLive

  @sample_rows [
    %{
      id: "1",
      name: "Alice",
      email: "alice@test.com",
      active: true,
      inserted_at: ~U[2026-01-15 10:00:00Z]
    },
    %{
      id: "2",
      name: "Bob",
      email: "bob@test.com",
      active: false,
      inserted_at: ~U[2026-02-20 12:00:00Z]
    },
    %{
      id: "3",
      name: "Charlie",
      email: "charlie@test.com",
      active: true,
      inserted_at: ~U[2026-03-10 08:00:00Z]
    },
    %{
      id: "4",
      name: "Diana",
      email: "diana@test.com",
      active: true,
      inserted_at: ~U[2026-04-05 14:00:00Z]
    }
  ]

  @columns [
    Column.new(:name, sortable: true, searchable: true),
    Column.new(:email, sortable: true, searchable: true),
    Column.new(:active),
    Column.new(:inserted_at, sortable: true)
  ]

  @filters [
    %Filter{type: :boolean, field: :active, label: "Active"},
    %Filter{type: :date_range, field: :inserted_at, label: "Inserted At"},
    %Filter{
      type: :select,
      field: :name,
      label: "Name",
      options: ["Alice", "Bob", "Charlie", "Diana"]
    }
  ]

  # ---------------------------------------------------------------------------
  # apply_search/3
  # ---------------------------------------------------------------------------

  describe "apply_search/3" do
    test "returns all rows when search is nil" do
      result = InMemoryTableLive.apply_search(@sample_rows, nil, @columns)
      assert result == @sample_rows
    end

    test "returns all rows when search is empty string" do
      result = InMemoryTableLive.apply_search(@sample_rows, "", @columns)
      assert result == @sample_rows
    end

    test "filters rows by name (searchable column)" do
      result = InMemoryTableLive.apply_search(@sample_rows, "alice", @columns)
      assert length(result) == 1
      assert hd(result).name == "Alice"
    end

    test "filters rows by email (searchable column)" do
      result = InMemoryTableLive.apply_search(@sample_rows, "bob@test.com", @columns)
      assert length(result) == 1
      assert hd(result).name == "Bob"
    end

    test "search is case-insensitive" do
      result = InMemoryTableLive.apply_search(@sample_rows, "CHARLIE", @columns)
      assert length(result) == 1
      assert hd(result).name == "Charlie"
    end

    test "partial match works" do
      result = InMemoryTableLive.apply_search(@sample_rows, "test.com", @columns)
      assert length(result) == 4
    end

    test "non-searchable columns are not searched" do
      # :active and :inserted_at are not searchable — searching for "true" should return nothing
      result = InMemoryTableLive.apply_search(@sample_rows, "true", @columns)
      assert result == []
    end

    test "returns empty list when no match" do
      result = InMemoryTableLive.apply_search(@sample_rows, "zzznomatch", @columns)
      assert result == []
    end

    test "partial name match returns multiple rows" do
      result = InMemoryTableLive.apply_search(@sample_rows, "a", @columns)

      # Alice (name), Charlie (name + email has no 'a'), Diana (name), bob@test.com no 'a' in name... alice@test.com has 'a'
      # Alice: name="Alice" -> "alice" contains "a" ✓
      # Bob: name="Bob", email="bob@test.com" -> neither contains "a" — wait "bob@test.com" has no 'a'... actually it doesn't
      # Charlie: name="Charlie" -> "charlie" contains "a" ✓; also email "charlie@test.com" contains "a" ✓
      # Diana: name="Diana" -> "diana" contains "a" ✓
      names = Enum.map(result, & &1.name)
      assert "Alice" in names
      assert "Charlie" in names
      assert "Diana" in names
      refute "Bob" in names
    end
  end

  # ---------------------------------------------------------------------------
  # apply_sort/3
  # ---------------------------------------------------------------------------

  describe "apply_sort/3" do
    test "sorts by string column ascending" do
      result = InMemoryTableLive.apply_sort(@sample_rows, :name, :asc)
      names = Enum.map(result, & &1.name)
      assert names == ["Alice", "Bob", "Charlie", "Diana"]
    end

    test "sorts by string column descending" do
      result = InMemoryTableLive.apply_sort(@sample_rows, :name, :desc)
      names = Enum.map(result, & &1.name)
      assert names == ["Diana", "Charlie", "Bob", "Alice"]
    end

    test "sorts by DateTime ascending" do
      result = InMemoryTableLive.apply_sort(@sample_rows, :inserted_at, :asc)
      dates = Enum.map(result, & &1.inserted_at)

      assert dates == [
               ~U[2026-01-15 10:00:00Z],
               ~U[2026-02-20 12:00:00Z],
               ~U[2026-03-10 08:00:00Z],
               ~U[2026-04-05 14:00:00Z]
             ]
    end

    test "sorts by DateTime descending" do
      result = InMemoryTableLive.apply_sort(@sample_rows, :inserted_at, :desc)
      dates = Enum.map(result, & &1.inserted_at)

      assert dates == [
               ~U[2026-04-05 14:00:00Z],
               ~U[2026-03-10 08:00:00Z],
               ~U[2026-02-20 12:00:00Z],
               ~U[2026-01-15 10:00:00Z]
             ]
    end

    test "sorts by id (string as number-like) ascending" do
      result = InMemoryTableLive.apply_sort(@sample_rows, :id, :asc)
      ids = Enum.map(result, & &1.id)
      assert ids == ["1", "2", "3", "4"]
    end

    test "nil values sort last ascending" do
      rows = [
        %{name: "Zara", val: nil},
        %{name: "Alice", val: 1},
        %{name: "Bob", val: 2}
      ]

      result = InMemoryTableLive.apply_sort(rows, :val, :asc)
      assert List.last(result).name == "Zara"
    end

    test "nil values sort last descending" do
      rows = [
        %{name: "Zara", val: nil},
        %{name: "Alice", val: 1},
        %{name: "Bob", val: 2}
      ]

      result = InMemoryTableLive.apply_sort(rows, :val, :desc)
      assert List.last(result).name == "Zara"
    end

    test "sorts numbers ascending" do
      rows = [
        %{name: "C", score: 30},
        %{name: "A", score: 10},
        %{name: "B", score: 20}
      ]

      result = InMemoryTableLive.apply_sort(rows, :score, :asc)
      scores = Enum.map(result, & &1.score)
      assert scores == [10, 20, 30]
    end

    test "sorts numbers descending" do
      rows = [
        %{name: "C", score: 30},
        %{name: "A", score: 10},
        %{name: "B", score: 20}
      ]

      result = InMemoryTableLive.apply_sort(rows, :score, :desc)
      scores = Enum.map(result, & &1.score)
      assert scores == [30, 20, 10]
    end

    test "sorts by Date ascending" do
      rows = [
        %{name: "C", born: ~D[2000-03-01]},
        %{name: "A", born: ~D[1990-01-15]},
        %{name: "B", born: ~D[1995-06-20]}
      ]

      result = InMemoryTableLive.apply_sort(rows, :born, :asc)
      names = Enum.map(result, & &1.name)
      assert names == ["A", "B", "C"]
    end
  end

  # ---------------------------------------------------------------------------
  # apply_pagination/3
  # ---------------------------------------------------------------------------

  describe "apply_pagination/3" do
    test "returns first page with correct rows" do
      {rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 1, 2)
      assert length(rows) == 2
      assert hd(rows).name == "Alice"
      assert meta.page == 1
      assert meta.per_page == 2
      assert meta.total == 4
    end

    test "returns second page" do
      {rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 2, 2)
      assert length(rows) == 2
      assert hd(rows).name == "Charlie"
      assert meta.page == 2
    end

    test "returns partial last page" do
      {rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 2, 3)
      assert length(rows) == 1
      assert hd(rows).name == "Diana"
      assert meta.total == 4
    end

    test "returns empty list for out-of-range page" do
      {rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 99, 10)
      assert rows == []
      assert meta.page == 99
      assert meta.total == 4
    end

    test "per_page larger than total returns all rows on page 1" do
      {rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 1, 100)
      assert length(rows) == 4
      assert meta.total == 4
    end

    test "returns correct total regardless of page" do
      {_rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 3, 2)
      assert meta.total == 4
    end

    test "meta includes correct per_page" do
      {_rows, meta} = InMemoryTableLive.apply_pagination(@sample_rows, 1, 3)
      assert meta.per_page == 3
    end

    test "empty list returns empty with zero total" do
      {rows, meta} = InMemoryTableLive.apply_pagination([], 1, 10)
      assert rows == []
      assert meta.total == 0
    end
  end

  # ---------------------------------------------------------------------------
  # apply_filters/3
  # ---------------------------------------------------------------------------

  describe "apply_filters/3" do
    test "returns all rows when active_filters is empty" do
      result = InMemoryTableLive.apply_filters(@sample_rows, %{}, @filters)
      assert result == @sample_rows
    end

    test "boolean filter true returns only active rows" do
      result = InMemoryTableLive.apply_filters(@sample_rows, %{active: "true"}, @filters)
      assert length(result) == 3
      assert Enum.all?(result, &(&1.active == true))
    end

    test "boolean filter false returns only inactive rows" do
      result = InMemoryTableLive.apply_filters(@sample_rows, %{active: "false"}, @filters)
      assert length(result) == 1
      assert hd(result).name == "Bob"
      assert hd(result).active == false
    end

    test "select filter matches string value" do
      result = InMemoryTableLive.apply_filters(@sample_rows, %{name: "Alice"}, @filters)
      assert length(result) == 1
      assert hd(result).name == "Alice"
    end

    test "date_range filter returns rows within range" do
      # Range covers Feb and Mar: Bob (2026-02-20) and Charlie (2026-03-10)
      result =
        InMemoryTableLive.apply_filters(
          @sample_rows,
          %{inserted_at: "2026-02-01|2026-03-31"},
          @filters
        )

      names = Enum.map(result, & &1.name)
      assert length(result) == 2
      assert "Bob" in names
      assert "Charlie" in names
    end

    test "date_range filter excludes rows outside range" do
      # Only Alice: 2026-01-15
      result =
        InMemoryTableLive.apply_filters(
          @sample_rows,
          %{inserted_at: "2026-01-01|2026-01-31"},
          @filters
        )

      assert length(result) == 1
      assert hd(result).name == "Alice"
    end

    test "multiple filters compose with AND logic" do
      # active=true AND inserted_at in Feb-Mar → only Charlie (2026-03-10, active=true)
      # Bob is in range but active=false; Diana is active=true but inserted_at 2026-04-05 out of range
      result =
        InMemoryTableLive.apply_filters(
          @sample_rows,
          %{active: "true", inserted_at: "2026-02-01|2026-03-31"},
          @filters
        )

      assert length(result) == 1
      assert hd(result).name == "Charlie"
    end

    test "unknown filter field (no matching filter_def) is ignored" do
      # :nonexistent has no filter_def, so all rows returned
      result = InMemoryTableLive.apply_filters(@sample_rows, %{nonexistent: "value"}, @filters)
      assert result == @sample_rows
    end

    test "nil active filter value is ignored" do
      result = InMemoryTableLive.apply_filters(@sample_rows, %{active: nil}, @filters)
      assert result == @sample_rows
    end
  end
end
