<template>
  <TheMenubar />
  <main class="_3d-room h-screen w-screen flex items-center justify-center overflow-hidden">
    <slot />
  </main>
</template>

<style lang="scss">
._3d-room {
  height: 100vh;
}
</style>
