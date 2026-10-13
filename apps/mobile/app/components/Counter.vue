<script setup lang='ts'>
const { count, inc, dec } = useCount()
</script>

<template>
  <div class="inline-flex my-3">
    <button class="px-4 py-1 rounded-full p-2 inline-block bg-teal-600 text-white cursor-pointer hover:bg-teal-700" @click="dec()">
      <div class="i-carbon-subtract" />
    </button>
    <div class="font-mono w-15 m-auto inline-block">
      {{ count }}
    </div>
    <button class="px-4 py-1 rounded-full p-2 inline-block bg-teal-600 text-white cursor-pointer hover:bg-teal-700" @click="inc()">
      <div class="i-carbon-add" />
    </button>
  </div>
</template>
