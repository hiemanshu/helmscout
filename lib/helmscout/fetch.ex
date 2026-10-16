defmodule Helmscout.Fetch do
  @moduledoc """
  Materialises a source repository into the local cache directory.

  We keep roughly one year of history (`--shallow-since`) so per-file commit
  timestamps remain available for recency ranking, and limit blob size to keep
  clones small. Existing checkouts are fetched and hard-reset in place.
  """

  require Logger

  @shallow_since "1 year"

  @doc "Return the local checkout directory for a source (does not create it)."
  @spec dir_for(Helmscout.Source.t(), Path.t() | nil) :: Path.t()
  def dir_for(source, cache_dir \\ nil) do
    Path.join(cache_dir || cache_dir(), safe_dir(source.key || source.name))
  end

  @doc """
  Clone or update the checkout for `source`. Returns `{:ok, dir}`.
  """
  @spec checkout(Helmscout.Source.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def checkout(%Helmscout.Source{} = source, opts \\ []) do
    dir = dir_for(source, opts[:cache_dir])
    File.mkdir_p!(Path.dirname(dir))

    cond do
      File.dir?(Path.join(dir, ".git")) -> update(source, dir)
      File.exists?(dir) -> {:error, {:path_exists, dir}}
      true -> clone(source, dir)
    end
  end

  @doc """
  Current commit SHA of the source's default branch (via `git ls-remote`, so no
  clone or API call is needed). Returns `{:ok, sha}` or `:error`.
  """
  @spec remote_head(Helmscout.Source.t()) :: {:ok, String.t()} | :error
  def remote_head(%Helmscout.Source{url: url} = source) do
    case run(["ls-remote", "--heads", url, branch(source)]) do
      {:ok, out} ->
        case Regex.run(~r/^([0-9a-f]{40})\s/m, out) do
          [_, sha] -> {:ok, sha}
          _ -> :error
        end

      {:error, _} ->
        :error
    end
  end

  defp clone(source, dir) do
    base = ["clone", "--filter=blob:limit=1m", "--single-branch", "--branch", branch(source)]

    shallow = base ++ ["--shallow-since=#{@shallow_since}", source.url, dir]

    case run(shallow) do
      {:ok, _} ->
        {:ok, dir}

      {:error, _} ->
        # Some forges reject --shallow-since; fall back to a depth-1 clone.
        Logger.debug("shallow-since clone failed for #{source.name}, retrying depth=1")
        File.rm_rf(dir)

        case run(base ++ ["--depth", "1", source.url, dir]) do
          {:ok, _} -> {:ok, dir}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp update(source, dir) do
    with {:ok, _} <-
           run([
             "-C",
             dir,
             "fetch",
             "--quiet",
             "--shallow-since=#{@shallow_since}",
             "origin",
             branch(source)
           ]),
         {:ok, _} <- run(["-C", dir, "reset", "--hard", "--quiet", "FETCH_HEAD"]) do
      {:ok, dir}
    else
      {:error, reason} ->
        Logger.warning("update of #{source.name} failed (#{inspect(reason)}), re-cloning")
        File.rm_rf(dir)
        clone(source, dir)
    end
  end

  defp branch(%{branch: b}) when is_binary(b) and b != "", do: b
  defp branch(_), do: "main"

  defp run(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {code, out}}
    end
  rescue
    e -> {:error, e}
  end

  @doc false
  def safe_dir(name) do
    name
    |> to_string()
    |> String.replace("/", "-")
    |> String.replace(~r/[^A-Za-z0-9._-]/, "-")
  end

  defp cache_dir do
    Application.get_env(:helmscout, :cache_dir, "data/repos")
  end
end
