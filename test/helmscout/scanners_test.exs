defmodule Helmscout.ScannersTest do
  use ExUnit.Case, async: true

  alias Helmscout.{Manifest, Scanner}

  defp parse(yaml) do
    {:ok, docs} = Manifest.read_all(yaml)

    for doc <- docs,
        scanner <- Scanner.all(),
        result = scanner.parse(doc),
        result != :skip,
        release <- List.wrap(elem(result, 1)) do
      {scanner.name(), release}
    end
  end

  test "flux HelmRelease with a HelmRepository source" do
    [{"flux_helm_release", release}] =
      parse("""
      apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      metadata:
        name: immich
        namespace: media
      spec:
        chart:
          spec:
            chart: immich
            version: "9.x"
            sourceRef:
              kind: HelmRepository
              name: bjw-s
              namespace: flux-system
        values:
          ingress:
            main:
              annotations:
                hajimari.io/icon: immich
      """)

    assert release.chart_name == "immich"
    assert release.chart_version == "9.x"
    assert release.namespace == "media"
    assert release.chart_ref_kind == "HelmRepository"
    assert release.chart_source == "bjw-s"
    assert release.chart_source_namespace == "flux-system"
    assert release.icon == "immich"
    assert release.values =~ "immich"
  end

  test "flux HelmRelease using an OCIRepository chartRef" do
    [{"flux_helm_release", release}] =
      parse("""
      apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      metadata:
        name: cilium
      spec:
        chartRef:
          kind: OCIRepository
          name: cilium
          namespace: flux-system
      """)

    assert release.chart_name == "cilium"
    assert release.chart_ref_kind == "OCIRepository"
    assert release.chart_source == "cilium"
  end

  test "flux HelmRelease templates are skipped" do
    assert parse("""
           apiVersion: helm.toolkit.fluxcd.io/v2
           kind: HelmRelease
           metadata:
             name: "{{ .Release.Name }}"
           spec:
             chart:
               spec:
                 chart: foo
                 sourceRef:
                   kind: HelmRepository
                   name: bar
           """) == []
  end

  test "argo Application single source" do
    [{"argo_application", release}] =
      parse("""
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: jellyfin
      spec:
        destination:
          namespace: media
        source:
          repoURL: https://bjw-s-labs.github.io/helm-charts
          chart: jellyfin
          targetRevision: 1.0.0
      """)

    assert release.chart_name == "jellyfin"
    assert release.chart_version == "1.0.0"
    assert release.namespace == "media"
    assert release.chart_source == "https://bjw-s-labs.github.io/helm-charts"
  end

  test "argo Application multi-source picks the chart source" do
    [{"argo_application", release}] =
      parse("""
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: multi
      spec:
        sources:
          - repoURL: https://charts.example.com
            chart: grafana
            targetRevision: "*"
          - repoURL: https://github.com/x/y
            ref: values
      """)

    assert release.chart_name == "grafana"
  end

  test "argo ApplicationSet template" do
    [{"argo_application_set", release}] =
      parse("""
      apiVersion: argoproj.io/v1alpha1
      kind: ApplicationSet
      metadata:
        name: apps
      spec:
        template:
          spec:
            destination:
              namespace: default
            source:
              repoURL: https://charts.example.com
              chart: kube-prometheus-stack
              targetRevision: 60.0.0
      """)

    assert release.chart_name == "kube-prometheus-stack"
    assert release.namespace == "default"
  end

  test "argo ApplicationSet expands list generator variables" do
    results =
      parse("""
      apiVersion: argoproj.io/v1alpha1
      kind: ApplicationSet
      metadata:
        name: istio-multi-control
      spec:
        generators:
          - list:
              elements:
                - version: 1.18.5
                  revision: 1-18-5
                - version: 1.19.3
                  revision: 1-19-3
        template:
          metadata:
            name: 'istio-control-{{revision}}'
          spec:
            destination:
              namespace: istio-system
            sources:
              - repoURL: 'https://istio-release.storage.googleapis.com/charts'
                targetRevision: '{{version}}'
                helm:
                  valuesObject:
                    revision: '{{revision}}'
                chart: istiod
              - repoURL: 'https://github.com/istio/istio.git'
                targetRevision: HEAD
                ref: values
      """)

    assert length(results) == 2
    assert Enum.all?(results, fn {scanner, _} -> scanner == "argo_application_set" end)

    names = results |> Enum.map(fn {_, r} -> r.release_name end) |> Enum.sort()
    assert names == ["istio-control-1-18-5", "istio-control-1-19-3"]

    versions = results |> Enum.map(fn {_, r} -> r.chart_version end) |> Enum.sort()
    assert versions == ["1.18.5", "1.19.3"]

    [{_, first} | _] = results
    assert first.chart_name == "istiod"
    assert first.namespace == "istio-system"
    assert first.values =~ "1-18-5"
  end

  test "argo ApplicationSet without generators keeps a single release" do
    [{"argo_application_set", release}] =
      parse("""
      apiVersion: argoproj.io/v1alpha1
      kind: ApplicationSet
      metadata:
        name: apps
      spec:
        template:
          spec:
            destination:
              namespace: default
            source:
              repoURL: https://charts.example.com
              chart: kube-prometheus-stack
              targetRevision: 60.0.0
      """)

    assert release.chart_name == "kube-prometheus-stack"
    assert release.chart_version == "60.0.0"
  end

  test "pre_check? rejects unrelated content" do
    refute Helmscout.Scanners.FluxHelmRelease.pre_check?("kind: Deployment")
    refute Helmscout.Scanners.ArgoApplication.pre_check?("kind: Deployment")
    # needs the apiVersion marker as well as kind
    refute Helmscout.Scanners.FluxHelmRelease.pre_check?("kind: HelmRelease\nspec:\n")

    assert Helmscout.Scanners.FluxHelmRelease.pre_check?(
             "apiVersion: helm.toolkit.fluxcd.io/v2\nkind: HelmRelease\nspec:\n"
           )
  end
end
