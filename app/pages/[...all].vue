<script setup lang="ts">
const router = useRouter()
</script>

<template>
  <main p="x4 y30" text="center dark:gray-200">
    <div text-4xl>
      <div i-carbon-warning inline-block />
    </div>
    <div>Not found</div>
    <div>
      <ion-button m="3 t8" @click="router.back()">
        Back
      </ion-button>
    </div>
  </main>
</template>
