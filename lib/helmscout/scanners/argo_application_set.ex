defmodule Helmscout.Scanners.ArgoApplicationSet do
  @moduledoc """
  Argo CD `ApplicationSet` (`argoproj.io/*`) whose template deploys a Helm chart.

  ApplicationSets are templates: their `{{...}}` placeholders are filled from
  generators. We resolve the common case where the placeholders come from
  `list` generators (including lists nested in `matrix`/`merge`) and emit one
  release per generated element, so the UI shows real versions (e.g. `1.18.5`)
  instead of `{{version}}`.

  When a variable cannot be resolved the placeholder is left untouched, matching
  the previous behaviour.
  """

  @behaviour Helmscout.Scanner

  alias Helmscout.Manifest

  @api_version "argoproj.io"
  @kind "ApplicationSet"

  @impl true
  def name, do: "argo_application_set"

  @impl true
  def pre_check?(content) do
    String.contains?(content, @api_version) and
      String.contains?(content, "kind: #{@kind}") and
      String.contains?(content, "template:")
  end

  @impl true
  def parse(doc) do
    cond do
      not Manifest.matches?(doc, "apiVersion", &String.starts_with?(&1, @api_version)) -> :skip
      not Manifest.matches?(doc, "kind", &(&1 == @kind)) -> :skip
      not chart_present?(doc) -> :skip
      true -> build_all(doc)
    end
  end

  # --- building ---------------------------------------------------------------

  defp build_all(doc) do
    variables =
      case element_lists(Manifest.get(doc, "spec.generators")) do
        [] -> [nil]
        lists -> product(lists)
      end

    releases =
      variables
      |> Enum.map(&build(doc, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&{&1.release_name, &1.chart_name, &1.chart_version, &1.values})

    case releases do
      [] -> :skip
      [one] -> {:ok, one}
      many -> {:ok, many}
    end
  end

  defp build(doc, vars) do
    source = doc |> pick_source() |> render(vars)

    namespace =
      doc |> Manifest.get("spec.template.spec.destination.namespace") |> render(vars)

    %{
      release_name: release_name(doc, vars),
      chart_name: source["chart"],
      chart_version: source["targetRevision"],
      namespace: namespace,
      chart_ref_kind: "ApplicationSet",
      chart_source: source["repoURL"],
      chart_source_namespace: nil,
      values: values(source),
      icon: nil,
      group: nil
    }
  end

  defp release_name(doc, vars) do
    name =
      Manifest.get(doc, "spec.template.metadata.name") ||
        Manifest.get(doc, "metadata.name")

    render(name, vars)
  end

  defp chart_present?(doc) do
    Manifest.present?(doc, "spec.template.spec.source.chart") or
      case Manifest.get(doc, "spec.template.spec.sources") do
        sources when is_list(sources) -> Enum.any?(sources, &is_map_key(&1, "chart"))
        _ -> false
      end
  end

  defp pick_source(doc) do
    case Manifest.get(doc, "spec.template.spec.source.chart") do
      chart when is_binary(chart) ->
        Manifest.get(doc, "spec.template.spec.source") || %{}

      _ ->
        sources = Manifest.get(doc, "spec.template.spec.sources") || []
        Enum.find(sources, &(is_map(&1) and is_binary(Map.get(&1, "chart")))) || %{}
    end
  end

  defp values(source) do
    helm = source["helm"] || %{}
    raw = helm["valuesObject"] || decode_string(helm["values"])

    case raw do
      nil -> nil
      value -> Helmscout.Values.encode(value)
    end
  end

  defp decode_string(value) when is_binary(value) do
    case Manifest.read_all(value) do
      {:ok, [doc]} -> doc
      {:ok, docs} -> docs
      _ -> value
    end
  end

  defp decode_string(_), do: nil

  # --- generator variables ----------------------------------------------------

  # Collect every `list` generator's elements anywhere under `spec.generators`.
  @doc false
  def element_lists(nil), do: []
  def element_lists(list) when is_list(list), do: Enum.flat_map(list, &element_lists/1)

  def element_lists(map) when is_map(map) do
    own =
      case Map.get(map, "list") do
        %{"elements" => elements} when is_list(elements) -> [Enum.filter(elements, &is_map/1)]
        _ -> []
      end

    own ++ (map |> Map.values() |> Enum.flat_map(&element_lists/1))
  end

  def element_lists(_), do: []

  # Cartesian product of the element lists (matrix semantics).
  defp product(lists) do
    Enum.reduce(lists, [%{}], fn elements, acc ->
      for vars <- acc, element <- elements, do: Map.merge(vars, stringify(element))
    end)
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)

  # --- templating -------------------------------------------------------------

  @doc false
  def render(term, vars) when is_binary(term), do: replace(term, vars)

  def render(term, vars) when is_map(term),
    do: Map.new(term, fn {k, v} -> {k, render(v, vars)} end)

  def render(term, vars) when is_list(term), do: Enum.map(term, &render(&1, vars))
  def render(term, _vars), do: term

  defp replace(string, nil), do: string
  defp replace(string, vars) when map_size(vars) == 0, do: string

  defp replace(string, vars) do
    Regex.replace(~r/\{\{\s*([\w.\-]+)\s*\}\}/, string, fn _, key ->
      Map.get(vars, key, "{{#{key}}}")
    end)
  end
end
