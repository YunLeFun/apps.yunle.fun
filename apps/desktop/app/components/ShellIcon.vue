<script setup lang="ts">
const props = defineProps<{ name: string }>()
const paths: Record<string, string> = {
  search: 'm21 21-4.35-4.35 M19 11a8 8 0 1 1-16 0 8 8 0 0 1 16 0',
  explore: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20 M16.5 7.5l-3 6-6 3 3-6z',
  grid: 'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',
  clock: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20 M12 6v6l4 2',
  house: 'm3 10 9-7 9 7 M5 9v12h5v-7h4v7h5V9',
  pen: 'm16 3 5 5-12 12-6 1 1-6z M14 5l5 5',
  game: 'M7 7h10c3 0 4 3 5 10 .3 2-1 3-2.5 2L16 16H8l-3.5 3C3 20 1.7 19 2 17 3 10 4 7 7 7 M6 10v5 M3.5 12.5h5 M16 11h.01 M19 14h.01',
  tool: 'M14 6a5 5 0 0 0-6 6L3 17a3 3 0 0 0 4 4l5-5a5 5 0 0 0 6-6l-3 3-4-4 3-3z',
  spark: 'm12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5z',
  smile: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20 M8 9h.01 M16 9h.01 M7 14c2 4 8 4 10 0',
  code: 'm8 5-6 7 6 7 M16 5l6 7-6 7 M14 3l-4 18',
  info: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20 M12 11v6 M12 7h.01',
  sun: 'M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M12 2v2 M12 20v2 M2 12h2 M20 12h2 M5 5l1.5 1.5 M17.5 17.5 19 19 M5 19l1.5-1.5 M17.5 6.5 19 5',
  refresh: 'M20 7V2 M20 7h-5 M20 7a9 9 0 1 0 1 9',
  back: 'm14 6-6 6 6 6',
  forward: 'm10 6 6 6-6 6',
  close: 'm6 6 12 12 M6 18 18 6',
  chevron: 'm8 5 7 7-7 7',
}
const path = computed(() => paths[props.name] || paths.grid)
</script>

<template>
  <svg class="shell-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path :d="path" /></svg>
</template>

<style scoped>
.shell-icon {
  width: 18px;
  height: 18px;
  flex: none;
}
</style>
