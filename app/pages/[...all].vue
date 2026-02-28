<script setup lang="ts">
const router = useRouter()
</script>

<template>
  <main class="px-4 py-30 text-center dark:text-gray-200">
    <div class="text-4xl">
      <div class="i-carbon-warning inline-block" />
    </div>
    <div>Not found</div>
    <div>
      <ion-button class="m-3 mt-8" @click="router.back()">
        Back
      </ion-button>
    </div>
  </main>
</template>
