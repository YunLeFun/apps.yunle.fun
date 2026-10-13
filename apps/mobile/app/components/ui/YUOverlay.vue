<template>
  <div class="yu-overlay-backdrop" />
</template>

<style scoped>
/* ==================== 背景模糊层 ==================== */
.yu-overlay-backdrop {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(20px) saturate(120%);
  -webkit-backdrop-filter: blur(20px) saturate(120%);

  transition: backdrop-filter 0.2s ease;
}
</style>
