defmodule Helmscout.Scanners.ArgoApplication do
  @moduledoc """
  Argo CD `Application` (`argoproj.io/*`) that deploys a Helm chart.
  """

  @behaviour Helmscout.Scanner

  alias Helmscout.Manifest

  @api_version "argoproj.io"
  @kind "Application"

  @impl true
  def name, do: "argo_application"

  @impl true
  def pre_check?(content) do
    String.contains?(content, @api_version) and
      String.contains?(content, "kind: #{@kind}") and
      String.contains?(content, "repoURL")
  end

  @impl true
  def parse(doc) do
    cond do
      not Manifest.matches?(doc, "apiVersion", &String.starts_with?(&1, @api_version)) -> :skip
      not Manifest.matches?(doc, "kind", &(&1 == @kind)) -> :skip
      not chart_present?(doc) -> :skip
      true -> {:ok, build(doc)}
    end
  end

  # Single source (spec.source.chart) or multi-source (spec.sources[].chart).
  defp chart_present?(doc) do
    Manifest.present?(doc, "spec.source.chart") or
      case Manifest.get(doc, "spec.sources") do
        sources when is_list(sources) -> Enum.any?(sources, &is_map_key(&1, "chart"))
        _ -> false
      end
  end

  defp build(doc) do
    source = pick_source(doc)

    %{
      release_name: Manifest.get(doc, "metadata.name"),
      chart_name: source["chart"],
      chart_version: source["targetRevision"],
      namespace: Manifest.get(doc, "spec.destination.namespace"),
      chart_ref_kind: "Application",
      chart_source: source["repoURL"],
      chart_source_namespace: nil,
      values: values(source),
      icon: hajimari(source, "icon"),
      group: hajimari(source, "group")
    }
  end

  defp pick_source(doc) do
    case Manifest.get(doc, "spec.source.chart") do
      chart when is_binary(chart) ->
        Manifest.get(doc, "spec.source") || %{}

      _ ->
        sources = Manifest.get(doc, "spec.sources") || []

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

  defp hajimari(source, key) do
    path = ~s(helm.valuesObject.ingress.main.annotations.hajimari\\.io/#{key})

    case Manifest.get(source, path) do
      value when is_binary(value) -> String.trim(value)
      _ -> nil
    end
  end
end
