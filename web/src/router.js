import { createRouter, createWebHistory } from 'vue-router'

import SearchView from './views/SearchView.vue'
import AppView from './views/AppView.vue'
import SourcesView from './views/SourcesView.vue'
import StatsView from './views/StatsView.vue'
import McpView from './views/McpView.vue'
import AboutView from './views/AboutView.vue'

export default createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'search', component: SearchView },
    { path: '/app/:app', name: 'app', component: AppView, props: true },
    { path: '/sources', name: 'sources', component: SourcesView },
    { path: '/stats', name: 'stats', component: StatsView },
    { path: '/mcp', name: 'mcp', component: McpView },
    { path: '/about', name: 'about', component: AboutView },
    { path: '/:pathMatch(.*)*', redirect: '/' }
  ],
  scrollBehavior: () => ({ top: 0 })
})
