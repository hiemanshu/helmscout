defmodule Helmscout.Apps do
  @moduledoc """
  Infers the *application* behind a Helm release from its container images.

  Many releases use a generic chart (`app-template`, `common`, `raw`, …) so the
  chart name is useless for "most used apps". The container image repository
  usually names the real app, and image names differ from chart names, so we
  collect images from the values and derive an app name from them.

  Image repositories are normalised to `registry/path/name` (tag/digest
  stripped) and the app is the final path segment, e.g.
  `ghcr.io/immich-app/immich` -> `immich`.
  """

  # Charts that carry no app identity of their own.
  @generic_charts ~w(app-template common library raw default chart)

  # Image repos that are infrastructure, not "the app".
  @infra_images ~w(pause alpine busybox nginx docker.io/library/redis docker.io/library/postgres)

  @doc "JSON-encoded list of image repositories found under `values`, or `nil`."
  def images_json(nil), do: nil

  def images_json(values_json) when is_binary(values_json) do
    case images(values_json) do
      [] -> nil
      images -> Jason.encode!(images)
    end
  end

  @doc "List of normalised image repositories in a JSON values blob."
  def images(values_json) do
    case Jason.decode(values_json || "null") do
      {:ok, decoded} -> collect(decoded) |> Enum.uniq()
      _ -> []
    end
  end

  @doc "Best-guess app name for a release given its chart and image list."
  def app(chart_name, values_json) do
    images = images(values_json)
    app_from(chart_name, images)
  end

  @doc false
  def app_from(chart_name, images) do
    chart = normalize_chart(chart_name)

    cond do
      generic?(chart) and images != [] -> primary_app(images)
      is_binary(chart) and chart != "" -> chart
      images != [] -> primary_app(images)
      true -> nil
    end
  end

  defp primary_app(images) do
    images
    |> Enum.reject(&infra?/1)
    |> case do
      [] -> app_name(hd(images))
      [first | _] -> app_name(first)
    end
  end

  defp app_name(repo), do: repo |> String.split("/") |> List.last() |> String.downcase()

  defp normalize_chart(nil), do: nil
  defp normalize_chart(chart), do: chart |> to_string() |> String.trim() |> String.downcase()

  defp generic?(nil), do: false
  defp generic?(chart), do: chart in @generic_charts

  @doc """
  Recomputes `app`/`images` for existing releases from their stored values.

  Runs in the database only (no cloning), so it is cheap to run after upgrading
  or in CI. Returns the number of rows updated.
  """
  def backfill(batch_size \\ 500) do
    import Ecto.Query

    from(r in Helmscout.HelmRelease,
      where: not is_nil(r.values),
      select: {r.id, r.chart_name, r.values}
    )
    |> Helmscout.Repo.all()
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce(0, fn chunk, acc ->
      Enum.each(chunk, fn {id, chart_name, values_json} ->
        Helmscout.Repo.update_all(
          from(r in Helmscout.HelmRelease, where: r.id == ^id),
          set: [app: app(chart_name, values_json), images: images_json(values_json)]
        )
      end)

      acc + length(chunk)
    end)
  end

  defp infra?(image) do
    Enum.any?(@infra_images, fn infra ->
      image == infra or String.ends_with?(image, "/" <> infra)
    end)
  end

  # --- value walking ----------------------------------------------------------

  defp collect(map) when is_map(map) do
    Enum.flat_map(map, fn {key, value} ->
      collect_entry(to_string(key), value)
    end)
  end

  defp collect(list) when is_list(list), do: Enum.flat_map(list, &collect/1)
  defp collect(_), do: []

  defp collect_entry(key, value) when is_binary(value) do
    if key in ["repository", "image"] and image?(value), do: [strip(value)], else: []
  end

  defp collect_entry(_key, value), do: collect(value)

  @doc false
  def image?(value) do
    String.contains?(value, "/") and
      not String.starts_with?(value, ["http", "oci://", "file://"]) and
      not String.contains?(value, " ") and
      String.length(value) < 200 and
      Regex.match?(~r|^[a-z0-9][a-z0-9._-]*(:[0-9]+)?/[a-z0-9._/-]+$|i, value)
  end

  @doc "Strip tag/digest from an image reference."
  def strip(value) do
    value
    |> String.split("@")
    |> hd()
    |> maybe_strip_tag()
  end

  defp maybe_strip_tag(value) do
    parts = String.split(value, "/")

    case List.pop_at(parts, -1) do
      {last, rest} ->
        last = last |> String.split(":") |> hd()
        Enum.join(rest ++ [last], "/")
    end
  end
end
