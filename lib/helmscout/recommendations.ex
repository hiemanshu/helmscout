defmodule Helmscout.Recommendations do
  @moduledoc """
  Aggregates the most common settings across every install of each app.

  Each release's `values` JSON is flattened into `path = value` leaves and
  counted per app. Only settings shared by at least `#{2}` installs are kept,
  capped at 25 per app. The result is a small table the frontend loads on
  demand — far smaller than shipping every release's values to the browser.
  """

  import Ecto.Query

  alias Helmscout.{HelmRelease, Repo}

  @min_count 2
  @per_app 25
  @max_depth 8
  @max_value_len 120

  @doc "Most common settings across every install of `app`."
  @spec for_app(String.t(), atom()) :: [
          %{path: String.t(), value: String.t(), count: pos_integer(), total: pos_integer()}
        ]
  def for_app(app, scope \\ :api) do
    ids = Helmscout.Visibility.excluded_ids(scope)

    Repo.all(
      from r in HelmRelease,
        where: r.app == ^app and not is_nil(r.values) and r.source_id not in ^ids,
        select: r.values
    )
    |> aggregate(app)
  end

  defp aggregate(values_list, _app) do
    total = length(values_list)

    values_list
    |> counts()
    |> Enum.filter(fn {_key, count} -> count >= @min_count end)
    |> Enum.sort_by(fn {_key, count} -> -count end)
    |> Enum.take(@per_app)
    |> Enum.flat_map(fn {key, count} ->
      case String.split(key, <<0>>, parts: 2) do
        [path, value] -> [%{path: path, value: value, count: count, total: total}]
        _ -> []
      end
    end)
  end

  defp counts(values_list) do
    Enum.reduce(values_list, %{}, fn json, acc ->
      case Jason.decode(json) do
        {:ok, doc} when is_map(doc) ->
          doc
          |> leaves()
          |> Enum.reduce(acc, fn key, counts -> Map.update(counts, key, 1, &(&1 + 1)) end)

        _ ->
          acc
      end
    end)
  end

  defp leaves(doc), do: doc |> walk("", 0, MapSet.new()) |> MapSet.to_list()

  defp walk(node, _path, _depth, set) when is_list(node), do: set

  defp walk(node, path, depth, set) when is_map(node) and depth <= @max_depth do
    Enum.reduce(node, set, fn {key, value}, acc ->
      walk(value, join(path, key), depth + 1, acc)
    end)
  end

  defp walk(node, _path, _depth, set) when is_map(node), do: set

  defp walk(nil, _path, _depth, set), do: set

  defp walk(value, _path, _depth, set)
       when is_binary(value) and byte_size(value) > @max_value_len,
       do: set

  defp walk(value, path, _depth, set), do: MapSet.put(set, path <> <<0>> <> to_string(value))

  defp join("", key), do: to_string(key)
  defp join(path, key), do: path <> "." <> to_string(key)
end
