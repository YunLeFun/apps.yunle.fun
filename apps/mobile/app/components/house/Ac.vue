<script lang="ts" setup>
const siteUrl = 'https://ac.yunyoujun.cn'
</script>

<template>
  <!-- <div class="ac-container">
    <iframe class="pointer-events-none h-10/1 w-10/1 transform-origin-lt scale-10" :src="siteUrl" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" sandbox="" allowfullscreen />
  </div> -->

  <div class="ac-container">
    <div class="face ac-container__front" />
    <div class="face ac-container__back">
      <iframe
        class="pointer-events-none h-10/1 w-10/1 transform-origin-lt scale-10" :src="siteUrl" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
        sandbox="allow-scripts"
        allowfullscreen
      />
    </div>
    <div class="face ac-container__right" />
    <div class="face ac-container__left" />
    <div class="face ac-container__top" />
    <div class="face ac-container__bottom" />
  </div>
</template>

<style lang="scss">
@use '~/styles/scss/3d-room/mixins' as *;
@use '~/styles/scss/3d-room/vars' as *;

.ac-container {
  $width-el: 12.5vw;
  $height-el: 4vw;
  $depth-el: 0.125vw;

  position: absolute;
  left: 12vw;
  top: 1vw;
  width: 5vw;
  height: 0.5vw;

  transform: translateZ(19vw);

  @include cube($width-el, $height-el, $depth-el);
  &__front {
    background-repeat: no-repeat;
    background-size: contain;
    background-position: center;
  }
  &__back {
    background-color: $white-3;
    box-shadow:
      0.35vw 0.35vw 0.35vw rgba($neon-1, 0.2),
      -0.35vw 0.35vw 0.35vw rgba($neon-1, 0.2),
      -0.35vw -0.35vw 0.35vw rgba($neon-1, 0.2),
      0.35vw -0.35vw 0.35vw rgba($neon-1, 0.2);
  }
  &__right {
    background-color: $white-3;
  }
  &__left {
    background-color: $white-2;
  }
  &__top {
    background-color: $white-2;
  }
  &__bottom {
    background-color: $white-3;
  }
}
</style>
