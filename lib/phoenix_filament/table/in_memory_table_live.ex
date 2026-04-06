defmodule PhoenixFilament.Table.InMemoryTableLive do
  @moduledoc """
  Generic in-memory table LiveComponent.

  Drop-in replacement for `PhoenixFilament.Table.TableLive` that operates
  on in-memory lists instead of Ecto queries. Uses the same `Column`,
  `Filter`, `Action` structs and `TableRenderer` function components.

  ## Pipeline Functions

  Three public pipeline functions compose to produce a filtered, sorted, and
  paginated result from any enumerable of maps or structs:

      rows
      |> InMemoryTableLive.apply_search(search, columns)
      |> InMemoryTableLive.apply_sort(sort_by, sort_dir)
      |> InMemoryTableLive.apply_pagination(page, per_page)
  """

  use Phoenix.LiveComponent

  alias PhoenixFilament.Table.Filter

  # ---------------------------------------------------------------------------
  # Public pipeline functions
  # ---------------------------------------------------------------------------

  @doc """
  Filters `rows` by `search` term across columns with `searchable: true`.

  The search is case-insensitive and matches any substring across all
  searchable columns concatenated per row. Returns all rows when `search`
  is `nil` or `""`.
  """
  @spec apply_search(list(map()), String.t() | nil, list(PhoenixFilament.Column.t())) ::
          list(map())
  def apply_search(rows, search, _columns) when search in [nil, ""], do: rows

  def apply_search(rows, search, columns) do
    searchable_columns =
      Enum.filter(columns, fn col -> Keyword.get(col.opts, :searchable, false) end)

    term = String.downcase(search)

    Enum.filter(rows, fn row ->
      searchable_columns
      |> Enum.map(fn col ->
        row
        |> Map.get(col.name)
        |> to_string()
        |> String.downcase()
      end)
      |> Enum.join(" ")
      |> String.contains?(term)
    end)
  end

  @doc """
  Sorts `rows` by the given column name atom and direction (`:asc` or `:desc`).

  Handles `DateTime`, `Date`, strings, numbers, and `nil` values. `nil`
  values always sort last regardless of direction.
  """
  @spec apply_sort(list(map()), atom() | nil, :asc | :desc) :: list(map())
  def apply_sort(rows, nil, _sort_dir), do: rows
  def apply_sort(rows, _sort_by, nil), do: rows

  def apply_sort(rows, sort_by, sort_dir) do
    Enum.sort(rows, fn a, b ->
      val_a = Map.get(a, sort_by)
      val_b = Map.get(b, sort_by)
      compare_values(val_a, val_b, sort_dir)
    end)
  end

  @doc """
  Filters `rows` by `active_filters` using the matching logic defined in `filter_defs`.

  `active_filters` is a map of `%{field_atom => value_string}` — values are always
  strings (e.g. from URL params). `filter_defs` is a list of `%Filter{}` structs.

  Filters compose with AND logic. Returns all rows when `active_filters` is empty.
  Nil or missing values in `active_filters` are ignored. Fields in `active_filters`
  with no matching filter definition are also ignored.

  | Filter type  | Matching logic                                                  |
  |--------------|------------------------------------------------------------------|
  | `:select`    | `to_string(row[field]) == value`                                |
  | `:boolean`   | `"true"` → field is `true`; `"false"` → field is `false`       |
  | `:date_range`| `"from|to"` pipe-separated ISO dates; field supports DateTime  |
  """
  @spec apply_filters(list(map()), %{atom() => String.t() | nil}, list(Filter.t())) ::
          list(map())
  def apply_filters(rows, active_filters, _filter_defs) when map_size(active_filters) == 0,
    do: rows

  def apply_filters(rows, active_filters, filter_defs) do
    active_defs =
      Enum.reduce(filter_defs, [], fn %Filter{field: field} = filter_def, acc ->
        case Map.get(active_filters, field) do
          nil -> acc
          "" -> acc
          value -> [{filter_def, value} | acc]
        end
      end)

    if active_defs == [] do
      rows
    else
      Enum.filter(rows, fn row ->
        Enum.all?(active_defs, fn {filter_def, value} ->
          apply_single_filter(row, filter_def, value)
        end)
      end)
    end
  end

  @doc """
  Paginates `rows`, returning `{page_rows, meta}` where `meta` is a map with
  keys `:page`, `:per_page`, and `:total`.

  Returns an empty list for out-of-range pages.
  """
  @spec apply_pagination(list(map()), pos_integer(), pos_integer()) ::
          {list(map()), %{page: pos_integer(), per_page: pos_integer(), total: non_neg_integer()}}
  def apply_pagination(rows, page, per_page) do
    total = length(rows)
    offset = (page - 1) * per_page
    page_rows = Enum.slice(rows, offset, per_page)
    meta = %{page: page, per_page: per_page, total: total}
    {page_rows, meta}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # nil always sorts last regardless of direction.
  # For :asc  — nil loses to everything  (false = b comes first = nil goes last)
  # For :desc — after the main sort, the comparator is inverted, so we keep
  #             nil losing (false) so it still ends up last after the implicit
  #             reversal that Enum.sort does when the comparator returns false.
  defp compare_values(nil, nil, _dir), do: true
  defp compare_values(nil, _b, _dir), do: false
  defp compare_values(_a, nil, _dir), do: true

  defp compare_values(%DateTime{} = a, %DateTime{} = b, :asc) do
    DateTime.compare(a, b) != :gt
  end

  defp compare_values(%DateTime{} = a, %DateTime{} = b, :desc) do
    DateTime.compare(a, b) != :lt
  end

  defp compare_values(%Date{} = a, %Date{} = b, :asc) do
    Date.compare(a, b) != :gt
  end

  defp compare_values(%Date{} = a, %Date{} = b, :desc) do
    Date.compare(a, b) != :lt
  end

  defp compare_values(a, b, :asc) when is_number(a) and is_number(b), do: a <= b
  defp compare_values(a, b, :desc) when is_number(a) and is_number(b), do: a >= b

  defp compare_values(a, b, :asc) when is_binary(a) and is_binary(b), do: a <= b
  defp compare_values(a, b, :desc) when is_binary(a) and is_binary(b), do: a >= b

  defp compare_values(a, b, :asc), do: to_string(a) <= to_string(b)
  defp compare_values(a, b, :desc), do: to_string(a) >= to_string(b)

  # ---------------------------------------------------------------------------
  # Filter helpers
  # ---------------------------------------------------------------------------

  defp apply_single_filter(row, %Filter{type: :select, field: field}, value) do
    to_string(Map.get(row, field)) == value
  end

  defp apply_single_filter(row, %Filter{type: :boolean, field: field}, "true") do
    Map.get(row, field) == true
  end

  defp apply_single_filter(row, %Filter{type: :boolean, field: field}, "false") do
    Map.get(row, field) == false
  end

  defp apply_single_filter(_row, %Filter{type: :boolean}, _value), do: true

  defp apply_single_filter(row, %Filter{type: :date_range, field: field}, value) do
    with [from_str, to_str] <- String.split(value, "|", parts: 2),
         {:ok, from_date} <- Date.from_iso8601(from_str),
         {:ok, to_date} <- Date.from_iso8601(to_str) do
      row_date = row |> Map.get(field) |> to_date()

      case row_date do
        nil -> false
        date -> Date.compare(date, from_date) != :lt and Date.compare(date, to_date) != :gt
      end
    else
      _ -> true
    end
  end

  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%Date{} = d), do: d
  defp to_date(_), do: nil
end
