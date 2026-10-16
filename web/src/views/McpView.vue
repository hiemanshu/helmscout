<template>
  <div class="pa-2 pa-md-4">
    <div class="d-flex align-center mb-4">
      <h2 class="text-h6 font-weight-bold mb-0">mcp</h2>
      <v-spacer />
      <v-chip size="small" color="success" variant="tonal">live</v-chip>
    </div>

    <v-card variant="flat" color="surface" class="pa-5 mb-6">
      <div class="d-flex align-start ga-4">
        <v-icon icon="mdi-robot-outline" color="primary" size="30" />
        <div>
          <div class="text-body-1 mb-1">
            helmscout runs a <strong>model context protocol</strong> server, so agents can
            search charts, apps and values directly instead of guessing.
          </div>
          <div class="text-caption text-medium-emphasis">
            streamable http · json-rpc 2.0 · no auth required
          </div>
        </div>
      </div>
    </v-card>

    <!-- endpoint + setup -->
    <section class="mb-8">
      <div class="section-head">
        <v-icon icon="mdi-link-variant" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">endpoint</h2>
      </div>

      <v-sheet class="code-block d-flex align-center ga-2 pa-3" rounded>
        <code class="flex-grow-1">{{ endpoint }}</code>
        <v-btn icon="mdi-content-copy" size="small" variant="text" @click="copy(endpoint)" />
      </v-sheet>
    </section>

    <section class="mb-8">
      <div class="section-head">
        <v-icon icon="mdi-console" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">connect a client</h2>
      </div>

      <div class="text-subtitle-2 mb-2">opencode</div>
      <v-sheet class="code-block d-flex align-center ga-2 pa-3 mb-4" rounded>
        <code class="flex-grow-1">{{ opencodeCmd }}</code>
        <v-btn icon="mdi-content-copy" size="small" variant="text" @click="copy(opencodeCmd)" />
      </v-sheet>

      <div class="text-subtitle-2 mb-2">or hand-written config</div>
      <v-sheet class="code-block pa-3" rounded>
        <pre><code>{{ configSnippet }}</code></pre>
      </v-sheet>
      <div class="text-caption text-medium-emphasis mt-2">
        any MCP client with streamable http works — point it at the endpoint above.
      </div>
    </section>

    <section class="mb-8">
      <div class="section-head">
        <v-icon icon="mdi-tools" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">tools</h2>
        <v-chip size="x-small" variant="tonal">{{ tools.length }}</v-chip>
      </div>

      <v-table density="default">
        <thead>
          <tr><th>tool</th><th>description</th></tr>
        </thead>
        <tbody>
          <tr v-for="t in tools" :key="t.name">
            <td><code>{{ t.name }}</code></td>
            <td class="text-medium-emphasis">{{ t.description }}</td>
          </tr>
        </tbody>
      </v-table>
    </section>

    <section>
      <div class="section-head">
        <v-icon icon="mdi-flask-outline" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">try it</h2>
      </div>

      <v-sheet class="code-block pa-3" rounded>
        <pre><code>{{ curlSnippet }}</code></pre>
      </v-sheet>
    </section>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { mcpUrl } from '../api.js'

const endpoint = mcpUrl()
const opencodeCmd = `opencode mcp add helmscout --url ${endpoint}`

const configSnippet = `{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "helmscout": {
        "type": "remote",
        "url": "${endpoint}",
        "oauth": false
      }
    }
  }
}`

const curlSnippet = `curl -s ${endpoint} \\
  -H 'content-type: application/json' \\
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'`

const tools = [
  { name: 'search_helm_releases', description: 'filter releases by chart, source, namespace or manifest scanner' },
  { name: 'get_release_values', description: 'full values object for one release by id' },
  { name: 'popular_charts', description: 'most widely deployed charts' },
  { name: 'list_sources', description: 'indexed repositories, optionally filtered by name' },
  { name: 'get_stats', description: 'repositories, releases and distinct chart counts' }
]

async function copy(text) {
  try {
    await navigator.clipboard.writeText(text)
  } catch (e) {
    console.error(e)
  }
}
</script>

<style scoped>
.section-head {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}
.code-block {
  background: rgba(var(--v-theme-surface-variant), 0.5);
  border: 1px solid rgba(var(--v-border-color), 0.12);
  overflow: auto;
}
.code-block code,
.code-block pre {
  font-size: 12.5px;
  margin: 0;
  white-space: pre-wrap;
  word-break: break-all;
}
</style>
