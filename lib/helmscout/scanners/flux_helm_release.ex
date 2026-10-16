defmodule Helmscout.Scanners.FluxHelmRelease do
  @moduledoc """
  Flux `HelmRelease` (`helm.toolkit.fluxcd.io/*`).

  Handles both the `spec.chart.spec.*` shape (HelmRepository/GitRepository
  source) and the `spec.chartRef.*` shape (OCIRepository/HelmChart source).
  """

  @behaviour Helmscout.Scanner

  alias Helmscout.Manifest

  @api_version "helm.toolkit.fluxcd.io"
  @kind "HelmRelease"

  @impl true
  def name, do: "flux_helm_release"

  @impl true
  def pre_check?(content) do
    String.contains?(content, @api_version) and
      String.contains?(content, "kind: #{@kind}") and
      String.contains?(content, "spec:")
  end

  @impl true
  def parse(doc) do
    cond do
      not Manifest.matches?(doc, "apiVersion", &String.starts_with?(&1, @api_version)) -> :skip
      not Manifest.matches?(doc, "kind", &(&1 == @kind)) -> :skip
      not valid_name?(Manifest.get(doc, "metadata.name")) -> :skip
      not chart_present?(doc) -> :skip
      true -> {:ok, build(doc)}
    end
  end

  defp valid_name?(name) when is_binary(name), do: not String.contains?(name, "{{")
  defp valid_name?(_), do: false

  # Shape A: spec.chart.spec.chart ; Shape B: spec.chartRef.name
  defp chart_present?(doc) do
    Manifest.present?(doc, "spec.chart.spec.chart") or
      Manifest.present?(doc, "spec.chartRef.name")
  end

  defp build(doc) do
    chart_name =
      Manifest.get(doc, "spec.chart.spec.chart") || Manifest.get(doc, "spec.chartRef.name")

    %{
      release_name: Manifest.get(doc, "metadata.name"),
      chart_name: chart_name,
      chart_version: Manifest.get(doc, "spec.chart.spec.version"),
      namespace: Manifest.get(doc, "metadata.namespace"),
      chart_ref_kind:
        Manifest.get(doc, "spec.chart.spec.sourceRef.kind") ||
          Manifest.get(doc, "spec.chartRef.kind"),
      chart_source:
        Manifest.get(doc, "spec.chart.spec.sourceRef.name") ||
          Manifest.get(doc, "spec.chartRef.name"),
      chart_source_namespace:
        Manifest.get(doc, "spec.chart.spec.sourceRef.namespace") ||
          Manifest.get(doc, "spec.chartRef.namespace"),
      values: Helmscout.Values.encode(Manifest.get(doc, "spec.values")),
      icon: hajimari(doc, "icon"),
      group: hajimari(doc, "group")
    }
  end

  defp hajimari(doc, key) do
    path = ~s(spec.values.ingress.main.annotations.hajimari\\.io/#{key})

    case Manifest.get(doc, path) do
      value when is_binary(value) -> String.trim(value)
      _ -> nil
    end
  end
end
