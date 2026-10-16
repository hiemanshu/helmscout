defmodule Helmscout.Indexer do
  @moduledoc """
  Walks a checked-out repository and extracts Helm releases from its manifests.

  `scan_dir/2` is pure with respect to the database (it only reads the working
  tree and shells out to `git`) and returns release attribute maps. `index_source/2`
  persists the result, replacing any previous rows for that source.
  """

  require Logger

  import Ecto.Query

  alias Helmscout.{HelmRelease, Manifest, Repo, Scanner, Source}

  @max_file_bytes 1_000_000
  @ignore_dirs MapSet.new([".git", "node_modules", "vendor", "archive", ".archive", ".terraform"])

  @doc "Directory (relative to the source checkout) → prefix used to build the browsable URL."
  @spec scan_dir(Path.t(), Source.t()) :: {:ok, [map()]} | {:error, term()}
  def scan_dir(dir, %Source{} = source) do
    if File.dir?(dir) do
      do_scan_dir(dir, source)
    else
      {:error, {:no_checkout, dir}}
    end
  end

  defp do_scan_dir(dir, source) do
    scanners = Scanner.all()
    files = walk_yaml(dir, dir)

    releases =
      files
      |> Task.async_stream(&scan_file(&1, dir, source, scanners),
        ordered: false,
        max_concurrency: System.schedulers_online() * 2,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, releases} -> releases
        _ -> []
      end)

    {:ok, releases}
  end

  @doc "Scan and persist a source. Returns `{:ok, release_count}`."
  @spec index_source(Source.t(), keyword()) :: {:ok, non_neg_integer()}
  def index_source(%Source{} = source, opts \\ []) do
    dir = Keyword.fetch!(opts, :dir)
    do_index(source, dir, hide_mcp?(source, dir))
  end

  # Owner opt-out from MCP: a topic or a `.helmscout-hide-mcp` marker file in the
  # repo root (see Helmscout.Visibility).
  defp hide_mcp?(source, dir) do
    Helmscout.Visibility.hide_mcp_from_topics?(source.topics) or
      File.exists?(Path.join(dir, Helmscout.Visibility.marker_file()))
  end

  defp do_index(source, dir, hide_mcp?) do
    case scan_dir(dir, source) do
      {:ok, releases} ->
        now = DateTime.utc_now()
        now_secs = DateTime.truncate(now, :second)

        rows =
          Enum.map(releases, fn release ->
            release
            |> Map.put(:source_id, source.id)
            |> Map.put(:inserted_at, now)
            |> Map.put(:updated_at, now)
            |> Map.update(:commit_ts, nil, &truncate_seconds/1)
          end)

        head_sha = git(dir, ["rev-parse", "HEAD"])

        Repo.transaction(fn ->
          Repo.delete_all(from r in HelmRelease, where: r.source_id == ^source.id)

          rows
          |> Enum.chunk_every(200)
          |> Enum.each(fn chunk ->
            Repo.insert_all(HelmRelease, chunk)
          end)

          source
          |> Ecto.Changeset.change(
            release_count: length(rows),
            last_indexed_at: now_secs,
            last_commit_sha: head_sha,
            hide_mcp: hide_mcp?
          )
          |> Repo.update!()
        end)

        {:ok, length(rows)}

      {:error, reason} ->
        Logger.error("indexing #{source.name} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- scanning ---------------------------------------------------------------

  defp scan_file(file, root, source, scanners) do
    case File.stat(file) do
      {:ok, %{size: size}} when size > @max_file_bytes -> []
      {:ok, _} -> do_scan_file(file, root, source, scanners)
      _ -> []
    end
  end

  defp do_scan_file(file, root, source, scanners) do
    content = File.read!(file)

    applicable = Enum.filter(scanners, & &1.pre_check?(content))

    if applicable == [] do
      []
    else
      rel = Path.relative_to(file, root)
      url = file_url(source, rel)
      commit_ts = file_commit_time(root, rel)
      line_count = content |> String.split("\n") |> length()

      case Manifest.read_all(content) do
        {:ok, docs} ->
          docs
          |> Enum.flat_map(&parse_doc(&1, applicable))
          |> Enum.map(fn {scanner, attrs} ->
            Map.merge(attrs, %{
              scanner: scanner.name(),
              file_path: rel,
              file_url: url,
              lines: line_count,
              commit_ts: commit_ts,
              images: Helmscout.Apps.images_json(attrs[:values]),
              app: Helmscout.Apps.app(attrs[:chart_name], attrs[:values])
            })
          end)

        {:error, _} ->
          []
      end
    end
  rescue
    _ -> []
  end

  defp parse_doc(doc, scanners) when is_list(doc) do
    Enum.flat_map(doc, &parse_doc(&1, scanners))
  end

  defp parse_doc(doc, scanners) when is_map(doc) do
    Enum.flat_map(scanners, fn scanner ->
      case scanner.parse(doc) do
        {:ok, attrs} when is_list(attrs) -> Enum.map(attrs, &{scanner, &1})
        {:ok, attrs} -> [{scanner, attrs}]
        :skip -> []
      end
    end)
  end

  defp parse_doc(_doc, _scanners), do: []

  defp walk_yaml(root, dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          path = Path.join(dir, entry)

          cond do
            File.dir?(path) ->
              if MapSet.member?(@ignore_dirs, entry), do: [], else: walk_yaml(root, path)

            yaml?(entry) ->
              [path]

            true ->
              []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp yaml?(name), do: String.ends_with?(name, ".yaml") or String.ends_with?(name, ".yml")

  defp file_url(%Source{url: url, branch: branch, forge: forge}, rel) do
    base = String.trim_trailing(url, "/")
    branch = branch || "main"

    case forge do
      "gitlab" ->
        "#{base}/-/blob/#{branch}/#{rel}"

      forge when forge in ["gitea", "forgejo", "codeberg"] ->
        "#{base}/src/branch/#{branch}/#{rel}"

      _ ->
        "#{base}/blob/#{branch}/#{rel}"
    end
  rescue
    _ -> url
  end

  defp file_commit_time(root, rel) do
    case git(root, ["log", "-1", "--format=%ct", "--", rel]) do
      nil -> nil
      "" -> nil
      secs -> to_datetime(secs)
    end
  end

  defp to_datetime(secs) do
    case Integer.parse(String.trim(secs)) do
      {int, _} -> DateTime.from_unix!(int)
      :error -> nil
    end
  rescue
    _ -> nil
  end

  defp truncate_seconds(nil), do: nil
  defp truncate_seconds(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp truncate_seconds(other), do: other

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
