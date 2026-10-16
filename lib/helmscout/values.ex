defmodule Helmscout.Values do
  @moduledoc """
  JSON-encode YAML-derived values objects, coercing types Jason cannot encode
  (dates, times, atoms, tuples) into strings/lists first.
  """

  @doc "Encode a decoded YAML value to a JSON string, or `nil` when empty/invalid."
  @spec encode(term()) :: String.t() | nil
  def encode(nil), do: nil

  def encode(value) do
    case Jason.encode(sanitize(value)) do
      {:ok, json} -> json
      _ -> nil
    end
  end

  @doc false
  def sanitize(%DateTime{} = v), do: DateTime.to_iso8601(v)
  def sanitize(%NaiveDateTime{} = v), do: NaiveDateTime.to_iso8601(v)
  def sanitize(%Date{} = v), do: Date.to_iso8601(v)
  def sanitize(%Time{} = v), do: Time.to_iso8601(v)
  def sanitize(v) when is_struct(v), do: inspect(v)
  def sanitize(v) when is_map(v), do: Map.new(v, fn {k, val} -> {to_string(k), sanitize(val)} end)
  def sanitize(v) when is_list(v), do: Enum.map(v, &sanitize/1)
  def sanitize(v) when is_tuple(v), do: v |> Tuple.to_list() |> Enum.map(&sanitize/1)
  def sanitize(v) when is_atom(v), do: to_string(v)
  def sanitize(v), do: v
end
