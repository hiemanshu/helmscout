<template>
  <div class="pa-2 pa-md-4">
    <h2 class="text-h6 font-weight-bold mb-4">about helmscout</h2>

    <v-card variant="flat" color="surface" class="pa-5 mb-6">
      <p class="mb-0">
        helmscout indexes <strong>helm releases</strong> from public gitops repositories so you can
        see how real clusters configure a chart — its values, namespaces and images — and it exposes
        the index over an API and an <router-link to="/mcp">mcp server</router-link> for agents.
      </p>
    </v-card>

    <section class="mb-8">
      <div class="section-head">
        <v-icon icon="mdi-account-plus-outline" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">get your repo indexed</h2>
      </div>
      <p>
        add the <code>helmscout</code> (or <code>kubesearch</code> / <code>k8s-at-home</code>) topic
        to your repository and it is picked up automatically. repositories with no topics can be
        listed in the instance's <code>config/sources.yaml</code>.
      </p>
    </section>

    <section class="mb-8">
      <div class="section-head">
        <v-icon icon="mdi-eye-off-outline" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">opt out</h2>
      </div>
      <p>
        don't want your repository used by AI agents? add the
        <code>helmscout-hide-mcp</code> topic — or a <code>.helmscout-hide-mcp</code> file in your
        repository root. it stays on the website and the api; it is simply left out of the
        <router-link to="/mcp">mcp server</router-link>.
      </p>
      <p class="mb-0">
        to leave helmscout entirely, make the repository private — only public repositories are
        indexed.
      </p>
    </section>

    <section>
      <div class="section-head">
        <v-icon icon="mdi-database-outline" color="primary" size="20" />
        <h2 class="text-h6 font-weight-bold mb-0">data &amp; attribution</h2>
      </div>
      <p class="mb-0">
        helmscout only stores references and derived metadata from public repositories; the manifests
        and values remain under each repository's own licence. it is a self-hosted replacement for
        <a href="https://kubesearch.dev" target="_blank" rel="noopener">kubesearch.dev</a>.
      </p>
    </section>
  </div>
</template>

<style scoped>
.section-head {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}
</style>
