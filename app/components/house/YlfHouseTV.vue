<script lang="ts" setup>
const siteUrl = 'https://studio.yunle.fun'
</script>

<template>
  <div class="tv">
    <div class="face tv__front" />
    <div class="face tv__back" />
    <a :href="siteUrl" class="face tv__right cursor-pointer" target="_blank">
      <iframe class="pointer-events-none h-10/1 w-10/1 transform-origin-lt scale-10" :src="siteUrl" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" sandbox="" allowfullscreen />
    </a>
    <div class="face tv__left" />

    <div class="tv__left face" />
    <div class="face tv__top" />
    <div class="face tv__bottom" />
  </div>
</template>

<style lang="scss">
@use 'sass:color';
@use '~/styles/scss/3d-room/mixins' as *;
@use '~/styles/scss/3d-room/vars' as *;

.tv {
  $width-el: 0.5vw;
  $height-el: 6vw;
  $depth-el: 6vw;

  position: absolute;
  left: 1.51vw;
  top: 8vw;
  width: 0.5vw;
  height: 12vw;

  transform: translateZ(8vw);

  @include cube($width-el, $height-el, $depth-el);

  &__front {
    background-color: $black-3;
  }
  &__back {
    background-color: $black-3;
  }
  &__right {
    background-color: color.adjust($neon-1, $lightness: 15%);
    border: 0.125vw solid color.adjust($black-3, $lightness: 10%);
    &::before {
      content: '';
      position: absolute;
      width: 100%;
      height: 100%;
      box-shadow:
        0.125vw 0.125vw 1vw rgba($neon-1, 0.5),
        -0.125vw 0.125vw 1vw rgba($neon-1, 0.5),
        0.125vw -0.125vw 1vw rgba($neon-1, 0.5),
        -0.125vw -0.125vw 1vw rgba($neon-1, 0.5);

      // background-image: url('');
      background-size: cover;
      background-repeat: no-repeat;
      background-position: bottom;
      opacity: 0.8;
    }
    animation: pantalla-tv 0.25s infinite alternate;
  }
  &__left {
    display: flex;
    justify-content: center;
    align-items: center;
    background-color: $black-3;

    &::before {
      content: '';
      position: absolute;
      width: 13vw;
      height: 7vw;
      // background-image: radial-gradient(rgba(darken($neon-2, 5), 0.95), rgba(darken($neon-1, 5), 0.95));
      background-image: radial-gradient(
        rgba(color.adjust($neon-2, $lightness: -5%), 0.95),
        rgba(color.adjust($neon-1, $lightness: -5%), 0.95)
      );

      filter: blur(1.25vw);

      animation: luz-tv 0.25s infinite alternate;
    }
  }
  &__top {
    background-color: $black-3;
  }
  &__bottom {
    background-color: $black-3;
  }
}
</style>
