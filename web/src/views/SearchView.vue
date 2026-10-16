<template>
  <div class="pa-2 pa-md-4">
    <!-- Landing page: apps + discover -->
    <template v-if="isHome">
      <section class="mb-8">
        <div class="d-flex flex-wrap align-center mb-4 ga-2">
          <h1 class="text-h5 font-weight-bold mb-0">most deployed apps</h1>
          <v-spacer />
          <span class="text-caption text-medium-emphasis d-none d-sm-inline">
            generic <code>app-template</code> charts resolved to the real app
          </span>
        </div>

        <div class="app-grid">
          <v-card
            v-for="(a, i) in topApps"
            :key="a.app"
            class="app-card"
            variant="tonal"
            @click="go(a.app)"
          >
            <div class="card-top">
              <span class="rank">{{ i + 1 }}</span>
              <v-icon v-if="i < 3" icon="mdi-star" size="16" color="warning" />
            </div>
            <div class="card-name">{{ a.app }}</div>
            <div class="card-sub">{{ a.releases }} installs · {{ a.sources }} repos</div>
            <v-btn class="mt-3" variant="tonal" color="primary" size="small"
                   append-icon="mdi-arrow-right">explore</v-btn>
          </v-card>
        </div>
      </section>

      <section>
        <div class="d-flex align-center mb-4">
          <h2 class="text-h6 font-weight-bold mb-0">discover something new</h2>
          <v-spacer />
          <v-btn variant="tonal" size="small" prepend-icon="mdi-shuffle" @click="shuffle">shuffle</v-btn>
        </div>

        <div class="app-grid">
          <v-card
            v-for="a in discover"
            :key="a.app"
            class="app-card"
            variant="tonal"
            @click="go(a.app)"
          >
            <div class="card-top">
              <v-icon icon="mdi-creation-outline" size="20" color="secondary" />
            </div>
            <div class="card-name">{{ a.app }}</div>
            <div class="card-sub">only {{ a.releases }} install{{ a.releases === 1 ? '' : 's' }} so far</div>
            <v-btn class="mt-3" variant="tonal" color="secondary" size="small"
                   append-icon="mdi-arrow-right">explore</v-btn>
          </v-card>
        </div>
      </section>
    </template>

    <!-- Search results -->
    <template v-else>
      <v-card variant="flat" class="mb-4 filter-bar" color="surface">
        <div class="d-flex flex-wrap align-center ga-3 pa-3">
          <div class="text-subtitle-2 text-medium-emphasis">
            <span v-if="source">source: <strong>{{ source }}</strong></span>
            <span v-else>{{ releases.length }} results</span>
          </div>
          <v-spacer class="d-none d-sm-flex" />
          <v-select
            v-model="sort"
            :items="sortOptions"
            label="sort"
            density="compact"
            variant="outlined"
            hide-details
            style="max-width: 210px"
          />
          <v-select
            v-model="scanner"
            :items="scannerOptions"
            label="manifest"
            density="compact"
            variant="outlined"
            hide-details
            clearable
            style="max-width: 210px"
          />
          <v-select
            v-model="forge"
            :items="forgeOptions"
            label="forge"
            density="compact"
            variant="outlined"
            hide-details
            clearable
            style="max-width: 150px"
          />
          <v-btn v-if="source" variant="text" size="small" @click="clearSource">clear source</v-btn>
        </div>
      </v-card>

      <ReleaseTable :releases="releases" />
    </template>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../api.js'
import { ui, homeData } from '../store.js'
import ReleaseTable from '../components/ReleaseTable.vue'

const route = useRoute()
const router = useRouter()

const releases = ref([])
const sort = ref('popular')
const scanner = ref(null)
const forge = ref(null)
const limit = ref(150)
const discover = ref([])

const sortOptions = [
  { title: 'most deployed', value: 'popular' },
  { title: 'recently updated', value: 'recent' },
  { title: 'alphabetical', value: 'name' }
]
const scannerOptions = [
  { title: 'flux helmrelease', value: 'flux_helm_release' },
  { title: 'argo application', value: 'argo_application' },
  { title: 'argo applicationset', value: 'argo_application_set' }
]
const forgeOptions = ['github', 'gitlab', 'codeberg', 'gitea', 'forgejo']

const topApps = computed(() => (homeData()?.top_apps || []).slice(0, 20))
const source = computed(() => route.query.source || '')
const isHome = computed(() => !ui.search && !source.value)

function shuffle(count = 5) {
  const pool = [...(homeData()?.discover_pool || [])]
  const picked = []
  while (picked.length < count && pool.length) {
    picked.push(pool.splice(Math.floor(Math.random() * pool.length), 1)[0])
  }
  discover.value = picked
}

let generation = 0
let runTimer

async function run() {
  const gen = ++generation

  if (isHome.value) {
    releases.value = []
    return
  }

  try {
    const data = await api.releases({
      q: ui.search,
      scanner: scanner.value || '',
      forge: forge.value || '',
      source: source.value,
      sort: sort.value,
      limit: limit.value
    })
    if (gen !== generation) return
    releases.value = data.releases
  } catch (e) {
    if (gen !== generation) return
    console.error(e)
    releases.value = []
  }
}

function go(app) {
  router.push(`/app/${encodeURIComponent(app)}`)
}
function clearSource() {
  router.push('/')
}

// Debounce the keystroke-driven watch: every character used to fire a network
// request, and the generation counter in run() drops late responses so the
// list always matches the last query.
function scheduleRun() {
  clearTimeout(runTimer)
  runTimer = setTimeout(run, 250)
}

watch([() => ui.search, sort, scanner, forge, source], scheduleRun)
watch(isHome, (home) => {
  if (home && !discover.value.length) shuffle()
})

onMounted(() => {
  shuffle()
  run()
})

onUnmounted(() => clearTimeout(runTimer))
</script>

<style scoped>
.app-grid {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 14px;
}
@media (max-width: 1100px) {
  .app-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}
@media (max-width: 640px) {
  .app-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
  }
}
.app-card {
  padding: 16px;
  border-radius: 12px;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  min-height: 150px;
  transition: transform 0.12s ease, box-shadow 0.12s ease;
}
.app-card:hover {
  transform: translateY(-2px);
}
.card-top {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 24px;
  margin-bottom: 6px;
}
.card-name {
  font-size: 1.15rem;
  font-weight: 600;
  line-height: 1.3;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
}
.card-sub {
  font-size: 12px;
  opacity: 0.65;
}
.app-card .v-btn {
  margin-top: auto;
}
.rank {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 22px;
  height: 22px;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 700;
  background: rgba(127, 127, 127, 0.18);
  flex: 0 0 auto;
}
.filter-bar {
  border-radius: 10px;
}
</style>
