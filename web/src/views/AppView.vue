<template>
  <div class="pa-2 pa-md-4">
    <v-btn variant="text" size="small" prepend-icon="mdi-arrow-left" to="/" class="mb-2">back to search</v-btn>

    <v-card variant="flat" color="surface" class="mb-6 pa-4">
      <div class="d-flex flex-wrap align-center ga-4">
        <div>
          <div class="text-h5 font-weight-bold">{{ app }}</div>
          <div class="text-medium-emphasis">
            {{ installTotal.toLocaleString() }} installs across {{ repoTotal.toLocaleString() }} repositories
          </div>
        </div>
        <v-spacer />
        <v-chip color="primary" variant="tonal">{{ charts.length }} chart{{ charts.length === 1 ? '' : 's' }}</v-chip>
      </div>
    </v-card>

    <!-- Repositories + installs -->
    <section class="mb-8">
      <div class="section-head">
        <v-icon icon="mdi-source-repository" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">repositories &amp; installs</h2>
        <v-chip size="x-small" variant="tonal">{{ releases.length }}</v-chip>
        <v-spacer />
        <span class="text-caption text-medium-emphasis">showing {{ visibleInstalls.length }}</span>
      </div>

      <ReleaseTable :releases="visibleInstalls" />

      <div v-if="visibleInstalls.length < releases.length" class="text-center mt-3">
        <v-btn variant="text" size="small" @click="installLimit += 10">
          load more ({{ releases.length - visibleInstalls.length }})
        </v-btn>
      </div>
    </section>

    <!-- Most common values -->
    <section>
      <div class="section-head">
        <v-icon icon="mdi-code-braces" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">most common values</h2>
        <v-chip v-if="valuesState === 'ready'" size="x-small" variant="tonal">
          {{ valuesResult.rows.length }}
        </v-chip>
        <v-spacer />
        <span v-if="valuesState === 'ready'" class="text-caption text-medium-emphasis">
          across {{ valuesResult.total }} installs
        </span>
      </div>

      <div v-if="valuesState === 'loading'" class="text-center py-6">
        <v-progress-circular indeterminate color="primary" size="36" />
        <div class="text-caption text-medium-emphasis mt-2">analysing values…</div>
      </div>

      <v-alert v-else-if="valuesState === 'error'" type="warning" variant="tonal" density="compact">
        could not analyse values
      </v-alert>

      <template v-else-if="valuesState === 'ready'">
        <v-alert v-if="!valuesResult.rows.length" type="info" variant="tonal" density="compact">
          no settings are shared by at least two installs
        </v-alert>

        <v-table v-else density="default">
          <thead>
            <tr>
              <th>setting</th>
              <th>value</th>
              <th style="width: 34%">adoption</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in visibleValues" :key="row.path + row.value">
              <td><code>{{ row.path }}</code></td>
              <td><code class="value-cell">{{ row.value }}</code></td>
              <td>
                <div class="d-flex align-center ga-2">
                  <v-progress-linear :model-value="row.pct * 100" color="secondary" height="8" rounded
                                     style="flex: 1" />
                  <span class="text-caption" style="min-width: 52px; text-align: right">
                    {{ row.count }}/{{ valuesResult.total }}
                  </span>
                </div>
              </td>
            </tr>
          </tbody>
        </v-table>

        <div v-if="visibleValues.length < valuesResult.rows.length" class="text-center mt-3">
          <v-btn variant="text" size="small" @click="valuesLimit += 10">
            load more ({{ valuesResult.rows.length - visibleValues.length }})
          </v-btn>
        </div>
      </template>
    </section>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { api } from '../api.js'
import ReleaseTable from '../components/ReleaseTable.vue'

const props = defineProps({ app: { type: String, required: true } })

const releases = ref([])
const summary = ref(null)
const installLimit = ref(10)
const valuesLimit = ref(10)
let generation = 0

const valuesState = ref('loading')
const valuesResult = ref({ total: 0, rows: [] })

const charts = computed(() => [...new Set(releases.value.map((r) => r.chart_name))])
const repos = computed(() => [...new Set(releases.value.map((r) => r.source?.name).filter(Boolean))])
// Exact totals come from the summary; the release list itself is capped (300).
const installTotal = computed(() => summary.value?.releases ?? releases.value.length)
const repoTotal = computed(() => summary.value?.sources ?? repos.value.length)
const visibleInstalls = computed(() => releases.value.slice(0, installLimit.value))
const visibleValues = computed(() => valuesResult.value.rows.slice(0, valuesLimit.value))

async function computeValues(gen) {
  valuesState.value = 'loading'

  try {
    const { rows } = await api.recommendations(props.app)
    if (gen !== generation) return
    const total = rows.length ? rows[0].total : 0

    valuesResult.value = {
      total,
      rows: rows.map((r) => ({
        path: r.path,
        value: r.value,
        count: r.count,
        pct: total ? r.count / total : 0
      }))
    }

    valuesState.value = 'ready'
  } catch (e) {
    if (gen !== generation) return
    console.error(e)
    valuesState.value = 'error'
  }
}

async function load() {
  const gen = ++generation
  installLimit.value = 10
  valuesLimit.value = 10
  summary.value = null
  valuesResult.value = { total: 0, rows: [] }
  computeValues(gen)

  try {
    const data = await api.app(props.app)
    if (gen !== generation) return
    summary.value = data.summary || null
    releases.value = data.releases
  } catch (e) {
    if (gen !== generation) return
    console.error(e)
    releases.value = []
  }
}

watch(() => props.app, load)
onMounted(load)
</script>

<style scoped>
.section-head {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}
.value-cell {
  color: rgb(var(--v-theme-accent));
}
</style>
