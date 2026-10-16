defmodule Helmscout.Discovery.Users do
  @moduledoc """
  Discovers every public repository of configured users/orgs, across forges.

  Configuration lives in a YAML file (default `config/sources.yaml`, override
  with `HELMSCOUT_SOURCES_CONFIG`) shaped as:

      users:
        github:
          - hiemanshu
        gitlab:
          - some-user
        codeberg:
          - someone
        "gitea:https://git.example.com":
          - someone

  This catches repos that carry no discovery topics (so topic search misses
  them) and sit too deep in code-search results to surface. Forks and archived
  repositories are skipped.
  """

  require Logger

  alias Helmscout.{Http, Manifest}
  alias Helmscout.Discovery.Github

  @per_page 100
  @gitea_per_page 50
  @max_pages 10

  @github_query """
  query($login: String!, $cursor: String) {
    repositoryOwner(login: $login) {
      __typename
      repositories(first: #{@per_page}, after: $cursor, isFork: false,
                   orderBy: {field: PUSHED_AT, direction: DESC}) {
        pageInfo { hasNextPage endCursor }
        nodes {
          nameWithOwner
          url
          stargazerCount
          pushedAt
          isArchived
          defaultBranchRef { name }
        }
      }
    }
  }
  """

  @spec candidates(keyword()) :: [map()]
  def candidates(opts \\ []) do
    entries = entries(opts)

    if entries == [] do
      []
    else
      Logger.info("      users: #{Enum.map_join(entries, ", ", fn {s, u} -> "#{s}/#{u}" end)}")

      repos =
        entries
        |> Task.async_stream(fn {service, username} -> fetch(service, username, opts) end,
          max_concurrency: length(entries),
          timeout: 300_000,
          ordered: false,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, repos} -> repos
          _ -> []
        end)

      Logger.info("      users: #{length(repos)} repos")
      repos
    end
  end

  # --- service dispatch -------------------------------------------------------

  defp fetch("github", username, opts), do: github_repos(username, opts)

  defp fetch("gitlab", username, opts), do: gitlab_repos(username, opts)

  defp fetch("codeberg", username, opts),
    do: gitea_repos("https://codeberg.org", "codeberg", username, opts)

  defp fetch("forgejo", username, opts),
    do: gitea_repos("https://codeberg.org", "forgejo", username, opts)

  defp fetch("gitea:" <> base, username, opts), do: gitea_repos(base, "gitea", username, opts)

  defp fetch(other, username, _opts) do
    Logger.warning("      users: unknown service #{inspect(other)} for #{username}")
    []
  end

  # --- GitHub -----------------------------------------------------------------

  defp github_repos(login, opts) do
    github_repos(login, nil, 1, Keyword.get(opts, :max_pages) || @max_pages, [])
  end

  defp github_repos(_login, _cursor, page, max_pages, acc) when page > max_pages, do: acc

  defp github_repos(login, cursor, page, max_pages, acc) do
    case Github.graphql(@github_query, %{"login" => login, "cursor" => cursor}) do
      {:ok, %{"repositoryOwner" => %{"repositories" => %{"nodes" => nodes} = conn}}}
      when is_list(nodes) ->
        acc =
          acc ++
            (nodes
             |> Enum.reject(& &1["isArchived"])
             |> Enum.map(&candidate(&1, "github_user:#{login}", "github")))

        if get_in(conn, ["pageInfo", "hasNextPage"]) do
          github_repos(login, get_in(conn, ["pageInfo", "endCursor"]), page + 1, max_pages, acc)
        else
          acc
        end

      {:ok, %{"repositoryOwner" => nil}} ->
        Logger.warning("      users: github user/org #{login} not found")
        []

      {:error, reason} ->
        Logger.warning("      users: github #{login} failed: #{inspect(reason)}")
        acc
    end
  end

  # --- GitLab -----------------------------------------------------------------

  defp gitlab_repos(username, opts) do
    case Http.get("https://gitlab.com/api/v4/users",
           params: [username: username]
         ) do
      {:ok, [%{"id" => id} | _]} ->
        gitlab_projects(id, username, 1, Keyword.get(opts, :max_pages) || @max_pages, [])

      {:ok, _} ->
        Logger.warning("      users: gitlab user #{username} not found")
        []

      {:error, reason} ->
        Logger.warning("      users: gitlab #{username} failed: #{inspect(reason)}")
        []
    end
  end

  defp gitlab_projects(_id, _username, page, max_pages, acc) when page > max_pages, do: acc

  defp gitlab_projects(id, username, page, max_pages, acc) do
    params = [per_page: @per_page, order_by: "last_activity_at", sort: "desc", page: page]

    case Http.get("https://gitlab.com/api/v4/users/#{id}/projects", params: params) do
      {:ok, projects} when is_list(projects) ->
        acc =
          acc ++
            Enum.map(projects, fn p ->
              %{
                name: p["path_with_namespace"],
                url: p["web_url"],
                forge: "gitlab",
                branch: p["default_branch"] || "main",
                stars: p["star_count"] || 0,
                pushed_at: Github.parse_time(p["last_activity_at"]),
                topics: p["topics"] || [],
                discoverer: "gitlab_user:#{username}"
              }
            end)

        if length(projects) < @per_page,
          do: acc,
          else: gitlab_projects(id, username, page + 1, max_pages, acc)

      {:error, reason} ->
        Logger.warning("      users: gitlab #{username} projects failed: #{inspect(reason)}")
        acc
    end
  end

  # --- Gitea / Codeberg / Forgejo ---------------------------------------------

  defp gitea_repos(base, forge, username, opts) do
    gitea_repos(base, forge, username, 1, Keyword.get(opts, :max_pages) || @max_pages, [])
  end

  defp gitea_repos(_base, _forge, _username, page, max_pages, acc) when page > max_pages, do: acc

  defp gitea_repos(base, forge, username, page, max_pages, acc) do
    params = [limit: @gitea_per_page, page: page]

    case Http.get("#{base}/api/v1/users/#{username}/repos", params: params) do
      {:ok, repos} when is_list(repos) ->
        acc =
          acc ++
            Enum.map(repos, fn repo ->
              %{
                name: repo["full_name"],
                url: repo["html_url"] || "#{base}/#{repo["full_name"]}",
                forge: forge,
                branch: repo["default_branch"] || "main",
                stars: repo["stars_count"] || 0,
                pushed_at: Github.parse_time(repo["updated_at"]),
                topics: repo["topics"] || [],
                discoverer: "#{forge}_user:#{username}"
              }
            end)

        if length(repos) < @gitea_per_page,
          do: acc,
          else: gitea_repos(base, forge, username, page + 1, max_pages, acc)

      {:error, reason} ->
        Logger.warning("      users: #{forge} #{username} failed: #{inspect(reason)}")
        acc
    end
  end

  # --- config -----------------------------------------------------------------

  defp candidate(node, discoverer, forge) do
    node
    |> Github.from_graphql(discoverer)
    |> Map.put(:forge, forge)
  end

  @doc "`{service, username}` pairs parsed from the config file."
  def entries(opts \\ []) do
    case Keyword.get(opts, :entries) do
      nil ->
        config_path()
        |> read_config()
        |> to_entries()

      entries ->
        entries
    end
  end

  defp read_config(path) do
    case File.read(path) do
      {:ok, content} ->
        case Manifest.read_all(content) do
          {:ok, [doc]} when is_map(doc) -> doc
          _ -> %{}
        end

      {:error, _} ->
        %{}
    end
  end

  defp to_entries(%{"users" => users}) when is_map(users) do
    for {service, value} <- users, username <- List.wrap(value), is_binary(username) do
      {to_string(service), String.trim(username)}
    end
  end

  defp to_entries(_), do: []

  defp config_path do
    System.get_env("HELMSCOUT_SOURCES_CONFIG") ||
      Enum.find(
        ["config/sources.yaml", "priv/sources.yaml"],
        "config/sources.yaml",
        &File.exists?/1
      )
  end
end
