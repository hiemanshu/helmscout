defmodule HelmscoutWeb.MCP do
  @moduledoc """
  Minimal Model Context Protocol server over the Streamable HTTP transport.

  Implements just enough of the protocol for tool use:

    * `initialize`
    * `notifications/initialized`, `ping`
    * `tools/list`
    * `tools/call`

  Requests are JSON-RPC 2.0 objects POSTed to `/mcp`. The body has already been
  parsed by the endpoint's `Plug.Parsers`, so we read `conn.body_params`.
  """

  @behaviour Plug

  require Logger

  alias Helmscout.Search

  @protocol_version "2025-06-18"
  @server_info %{name: "helmscout", version: "0.1.0"}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{method: "GET"} = conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(405, Jason.encode!(%{error: "use POST for MCP JSON-RPC"}))
  end

  def call(%{method: "POST"} = conn, _opts) do
    payload = conn.body_params

    case payload do
      requests when is_list(requests) ->
        responses = requests |> Enum.map(&handle/1) |> Enum.reject(&is_nil/1)
        respond(conn, responses)

      request when is_map(request) ->
        case handle(request) do
          nil -> Plug.Conn.resp(conn, 202, "")
          response -> respond(conn, response)
        end

      _ ->
        error(conn, nil, -32_700, "invalid request body")
    end
  end

  def call(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(405, Jason.encode!(%{error: "method not allowed"}))
  end

  # --- dispatch ---------------------------------------------------------------

  defp handle(%{"method" => "notifications/" <> _}), do: nil

  defp handle(%{"method" => "initialize"} = req) do
    result = %{
      protocolVersion: requested_version(req),
      capabilities: %{tools: %{listChanged: false}},
      serverInfo: @server_info
    }

    ok(req, result)
  end

  defp handle(%{"method" => "ping"} = req), do: ok(req, %{})

  defp handle(%{"method" => "tools/list"} = req) do
    ok(req, %{tools: Enum.map(tools(), &tool_descriptor/1)})
  end

  defp handle(%{"method" => "tools/call", "params" => params} = req) do
    name = params["name"]
    args = params["arguments"] || %{}

    case find_tool(name) do
      nil ->
        ok(req, error_result("unknown tool: #{inspect(name)}"))

      tool ->
        result =
          try do
            case tool.handler.(args) do
              {:ok, data} -> success_result(data)
              {:error, message} -> error_result(to_string(message))
            end
          rescue
            e ->
              Logger.warning("MCP tool #{name} crashed: #{Exception.message(e)}")
              error_result("tool crashed: #{Exception.message(e)}")
          end

        ok(req, result)
    end
  end

  defp handle(%{"method" => method} = req) do
    jsonrpc_error(req, -32_601, "method not found: #{method}")
  end

  defp handle(_), do: nil

  # --- JSON-RPC envelopes -----------------------------------------------------

  defp ok(%{"id" => id}, result), do: %{jsonrpc: "2.0", id: id, result: result}
  defp ok(_req, result), do: %{jsonrpc: "2.0", id: nil, result: result}

  defp jsonrpc_error(req, code, message) do
    %{jsonrpc: "2.0", id: Map.get(req, "id"), error: %{code: code, message: message}}
  end

  defp error(conn, id, code, message) do
    respond(conn, %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})
  end

  defp respond(conn, payload) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(200, Jason.encode!(payload))
  end

  defp requested_version(%{"params" => %{"protocolVersion" => version}}) when is_binary(version),
    do: version

  defp requested_version(_), do: @protocol_version

  # --- tool result helpers ----------------------------------------------------

  defp success_result(data) do
    %{
      content: [%{type: "text", text: text(data)}],
      structuredContent: structured(data),
      isError: false
    }
  end

  defp error_result(message) do
    %{content: [%{type: "text", text: message}], isError: true}
  end

  defp text(data) when is_binary(data), do: data
  defp text(data), do: Jason.encode!(data, pretty: true)

  defp structured(data) when is_map(data) or is_list(data), do: data
  defp structured(_), do: %{}

  defp tool_descriptor(tool) do
    %{name: tool.name, description: tool.description, inputSchema: tool.input_schema}
  end

  defp find_tool(name), do: Enum.find(tools(), &(&1.name == name))

  # --- tools ------------------------------------------------------------------

  defp tools do
    [
      %{
        name: "search_helm_releases",
        description:
          "Search individual Helm releases indexed from public home-ops/GitOps repos. " <>
            "Filter by chart name, source repo, namespace or manifest scanner.",
        input_schema: %{
          type: "object",
          properties: %{
            chart: %{type: "string", description: "Chart name substring, e.g. 'immich'"},
            source: %{type: "string", description: "Source repo substring, e.g. 'home-ops'"},
            namespace: %{type: "string", description: "Namespace substring"},
            scanner: %{
              type: "string",
              enum: ["flux_helm_release", "argo_application", "argo_application_set"],
              description: "Only releases of this manifest type"
            },
            limit: %{type: "integer", description: "Max results (default 20, max 100)"}
          }
        },
        handler: &tool_search_releases/1
      },
      %{
        name: "get_release_values",
        description: "Return the full values object for one Helm release by its numeric id.",
        input_schema: %{
          type: "object",
          properties: %{id: %{type: "integer", description: "Release id"}},
          required: ["id"]
        },
        handler: &tool_get_values/1
      },
      %{
        name: "popular_charts",
        description: "List the most widely deployed Helm charts across all indexed repos.",
        input_schema: %{
          type: "object",
          properties: %{limit: %{type: "integer", description: "Max results (default 50)"}}
        },
        handler: &tool_popular/1
      },
      %{
        name: "list_sources",
        description: "List indexed source repositories, optionally filtered by name.",
        input_schema: %{
          type: "object",
          properties: %{
            q: %{type: "string", description: "Name substring filter"},
            limit: %{type: "integer", description: "Max results (default 50)"}
          }
        },
        handler: &tool_sources/1
      },
      %{
        name: "get_stats",
        description: "Index statistics: number of source repos, releases and distinct charts.",
        input_schema: %{type: "object", properties: %{}},
        handler: &tool_stats/1
      }
    ]
  end

  defp tool_search_releases(args) do
    params =
      args
      |> Map.take(["chart", "source", "namespace", "scanner"])
      |> Map.put("limit", clamp(args["limit"], 20, 100))

    releases =
      Search.releases(params, :mcp)
      |> Enum.map(fn %{release: r, source: s} ->
        %{
          id: r.id,
          chart: r.chart_name,
          version: r.chart_version,
          release: r.release_name,
          namespace: r.namespace,
          scanner: r.scanner,
          repo: s.name,
          repo_url: s.url,
          file_url: r.file_url,
          commit_ts: r.commit_ts
        }
      end)

    {:ok, %{count: length(releases), releases: releases}}
  end

  defp tool_get_values(%{"id" => id}) when is_integer(id) do
    case Search.values(id, :mcp) do
      nil ->
        {:error, "no release with id #{id}"}

      %{release: release, values: values} ->
        {:ok,
         %{
           id: release.id,
           chart: release.chart_name,
           version: release.chart_version,
           repo: release.source && release.source.name,
           file_url: release.file_url,
           values: values
         }}
    end
  end

  defp tool_get_values(%{"id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> tool_get_values(%{"id" => int})
      :error -> {:error, "invalid id"}
    end
  end

  defp tool_get_values(_), do: {:error, "missing required argument: id"}

  defp tool_popular(args) do
    {:ok, %{charts: Search.popular(clamp(args["limit"], 50, 500), :mcp)}}
  end

  defp tool_sources(args) do
    params = %{"q" => args["q"], "limit" => clamp(args["limit"], 50, 500)}

    sources =
      Search.sources(params, :mcp)
      |> Enum.map(fn s ->
        %{name: s.name, url: s.url, forge: s.forge, stars: s.stars, releases: s.release_count}
      end)

    {:ok, %{count: length(sources), sources: sources}}
  end

  defp tool_stats(_args), do: {:ok, Search.stats(:mcp)}

  defp clamp(nil, default, max), do: min(default, max)
  defp clamp(value, _default, max) when is_integer(value), do: value |> max(1) |> min(max)
  defp clamp(_value, default, max), do: min(default, max)
end
