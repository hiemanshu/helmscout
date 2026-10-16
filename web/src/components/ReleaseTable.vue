<template>
  <v-table density="default" hover class="release-table">
    <thead>
      <tr>
        <th>app</th>
        <th class="d-none d-md-table-cell">namespace</th>
        <th class="d-none d-sm-table-cell">version</th>
        <th>repository</th>
        <th class="text-right">actions</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="r in releases" :key="r.id">
        <td>
          <router-link v-if="r.app" :to="`/app/${encodeURIComponent(r.app)}`" class="app-link">
            {{ r.app }}
          </router-link>
          <span v-else class="text-medium-emphasis">—</span>
          <div class="text-caption text-medium-emphasis">
            <code>{{ r.chart_name }}</code>
            <v-chip v-if="r.scanner === 'argo_application' || r.scanner === 'argo_application_set'" size="x-small" variant="tonal" color="accent" class="ml-1">argo</v-chip>
          </div>
        </td>
        <td class="d-none d-md-table-cell">{{ r.namespace || '—' }}</td>
        <td class="d-none d-sm-table-cell">{{ r.chart_version || '—' }}</td>
        <td>
          <a v-if="r.source" :href="r.source.url" target="_blank" rel="noopener" class="text-decoration-none">
            {{ r.source.name }}
            <v-icon icon="mdi-star" size="12" color="warning" class="ml-1" />{{ r.source.stars }}
          </a>
          <div class="text-caption text-medium-emphasis">{{ r.source?.forge }}</div>
        </td>
        <td class="text-right" style="white-space: nowrap">
          <v-tooltip text="view manifest" location="top">
            <template #activator="{ props }">
              <v-btn v-bind="props" icon="mdi-file-code-outline" size="small" variant="text"
                     :href="r.file_url" target="_blank" />
            </template>
          </v-tooltip>
          <v-btn size="small" variant="tonal" color="primary" prepend-icon="mdi-code-braces"
                 @click="open(r)">values</v-btn>
        </td>
      </tr>
      <tr v-if="!releases.length">
        <td colspan="5" class="text-center text-medium-emphasis py-8">no releases found</td>
      </tr>
    </tbody>
  </v-table>
</template>

<script setup>
import { openValues } from '../store.js'

defineProps({ releases: { type: Array, default: () => [] } })
const open = (r) => openValues(r)
</script>

<style scoped>
.app-link {
  font-weight: 600;
  text-decoration: none;
}

/* Two-line cells (app / chart, repo / forge) get even leading. */
.release-table :deep(.text-caption) {
  line-height: 1.6;
  margin-top: 4px;
}
</style>
