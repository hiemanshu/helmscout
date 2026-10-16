defmodule Helmscout.Manifest do
  @moduledoc """
  YAML loading and safe nested access for Kubernetes manifests.

  Paths use dot notation. A literal dot inside a map key is escaped with a
  backslash, e.g. `"metadata.annotations.hajimari\\.io/icon"`. This mirrors the
  traversal style used by the original k8s-at-home-search scanners while being
  tolerant of missing keys and non-map intermediates.
  """

  @type doc :: term()

  @doc "Parse every YAML document in `content`. Returns `{:ok, docs}` or `{:error, reason}`."
  @spec read_all(binary()) :: {:ok, [doc()]} | {:error, term()}
  def read_all(content) when is_binary(content) do
    case YamlElixir.read_all_from_string(content) do
      {:ok, docs} when is_list(docs) -> {:ok, Enum.reject(docs, &is_nil/1)}
      {:ok, doc} -> {:ok, [doc]}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Fetch a nested value by dotted `path`, returning `nil` when absent."
  @spec get(doc(), String.t()) :: term() | nil
  def get(doc, path) do
    Enum.reduce_while(split_path(path), doc, fn
      key, acc when is_map(acc) -> {:cont, Map.get(acc, key)}
      _key, _acc -> {:halt, nil}
    end)
  end

  @doc """
  True when the value at `path` is present and `pred` returns truthy for it.
  `pred` defaults to "anything but nil/false".
  """
  @spec matches?(doc(), String.t(), (term() -> boolean())) :: boolean()
  def matches?(doc, path, pred \\ &truthy?/1) do
    case get(doc, path) do
      nil -> false
      value -> pred.(value) == true
    end
  end

  @doc "True when the value at `path` is present (not nil)."
  def present?(doc, path), do: get(doc, path) != nil

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_), do: true

  @doc false
  def split_path(path) do
    path
    |> String.replace("\\.", <<0>>)
    |> String.split(".")
    |> Enum.map(&String.replace(&1, <<0>>, "."))
  end
end
