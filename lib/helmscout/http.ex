defmodule Helmscout.Http do
  @moduledoc """
  Thin wrapper around Req with the shared Finch pool, optional GitHub auth and
  basic retry/telemetry-free behaviour.
  """

  @doc "GET `url`. Returns `{:ok, body}` for 2xx JSON/body, else `{:error, reason}`."
  @spec get(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get(url, opts \\ []) do
    request =
      [url: url, headers: Keyword.get(opts, :headers, []), params: Keyword.get(opts, :params, [])] ++
        base_options(opts)

    case Req.get(request) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  @doc "POST a JSON body. Returns `{:ok, body}` or `{:error, reason}`."
  @spec post_json(String.t(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def post_json(url, body, opts \\ []) do
    request =
      [url: url, json: body, headers: Keyword.get(opts, :headers, [])] ++ base_options(opts)

    case Req.post(request) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp base_options(opts) do
    [finch: [name: Helmscout.Finch]] ++
      if(Keyword.get(opts, :decode, true), do: [decode_body: true], else: [])
  end

  @doc "GitHub API headers, including an auth token when one is available."
  @spec github_headers() :: [{String.t(), String.t()}]
  def github_headers do
    base = [
      {"accept", "application/vnd.github+json"},
      {"user-agent", "helmscout/0.1"},
      {"x-github-api-version", "2022-11-28"}
    ]

    case github_token() do
      nil -> base
      token -> [{"authorization", "Bearer #{token}"} | base]
    end
  end

  @doc "Resolve a GitHub token from env or the `gh` CLI, cached for the run."
  @spec github_token() :: String.t() | nil
  def github_token do
    case :persistent_term.get({__MODULE__, :github_token}, :unset) do
      :unset ->
        token = load_github_token()
        :persistent_term.put({__MODULE__, :github_token}, token)
        token

      token ->
        token
    end
  end

  defp load_github_token do
    System.get_env("GITHUB_TOKEN") || System.get_env("GH_TOKEN") || gh_cli_token()
  end

  defp gh_cli_token do
    case System.cmd("gh", ["auth", "token"], stderr_to_stdout: true) do
      {token, 0} -> String.trim(token)
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
