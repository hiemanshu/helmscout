<template>
  <div class="pa-2 pa-md-4">
    <div class="d-flex flex-wrap align-center ga-3 mb-4">
      <h2 class="text-h6 font-weight-bold mb-0">repositories</h2>
      <v-chip size="small" variant="tonal">{{ rows.length }}</v-chip>
      <v-spacer />
      <v-text-field
        v-model="q"
        density="compact"
        variant="outlined"
        hide-details
        prepend-inner-icon="mdi-magnify"
        placeholder="filter repositories…"
        clearable
        style="max-width: 280px"
      />
      <v-select
        v-model="forge"
        :items="forges"
        label="forge"
        density="compact"
        variant="outlined"
        hide-details
        clearable
        style="max-width: 160px"
      />
      <v-switch
        v-model="withReleases"
        label="indexed"
        color="primary"
        density="compact"
        hide-details
        inset
      />
    </div>

    <v-table density="comfortable" hover>
      <thead>
        <tr>
          <th>repository</th>
          <th class="d-none d-sm-table-cell">forge</th>
          <th class="text-right">stars</th>
          <th class="text-right">releases</th>
          <th class="d-none d-md-table-cell">last indexed</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="s in rows" :key="s.id" @click="openSource(s.name)" style="cursor: pointer">
          <td>
            <span class="font-weight-medium">{{ s.name }}</span>
            <div class="text-caption text-medium-emphasis">{{ s.branch }}</div>
          </td>
          <td class="d-none d-sm-table-cell">{{ s.forge }}</td>
          <td class="text-right">{{ (s.stars || 0).toLocaleString() }}</td>
          <td class="text-right">{{ (s.release_count || 0).toLocaleString() }}</td>
          <td class="d-none d-md-table-cell">{{ fmtDate(s.last_indexed_at) }}</td>
        </tr>
        <tr v-if="!rows.length">
          <td colspan="5" class="text-center text-medium-emphasis py-8">no repositories match</td>
        </tr>
      </tbody>
    </v-table>
  </div>
</template>

<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../api.js'

const router = useRouter()
const rows = ref([])
const q = ref('')
const forge = ref(null)
const withReleases = ref(true)
const forges = ['github', 'gitlab', 'codeberg', 'gitea', 'forgejo']

let generation = 0
let runTimer

async function run() {
  const gen = ++generation

  try {
    const data = await api.sources({
      q: q.value || '',
      forge: forge.value || '',
      with_releases: withReleases.value ? '1' : '',
      limit: 500
    })
    if (gen !== generation) return
    rows.value = data.sources
  } catch (e) {
    if (gen !== generation) return
    console.error(e)
    rows.value = []
  }
}

function openSource(name) {
  router.push({ path: '/', query: { source: name } })
}

function fmtDate(value) {
  if (!value) return '—'
  return String(value).slice(0, 10)
}

// Debounced watch (see SearchView): typing used to fire one request per key.
function scheduleRun() {
  clearTimeout(runTimer)
  runTimer = setTimeout(run, 250)
}

watch([q, forge, withReleases], scheduleRun)
onMounted(run)
onUnmounted(() => clearTimeout(runTimer))
</script>
