<template>
  <div class="cuadro-l">
    <div class="cuadro-l__front face" />
    <div class="cuadro-l__back face" />
    <div class="cuadro-l__right face" />
    <div class="cuadro-l__left face" />
    <div class="cuadro-l__top face" />
    <div class="cuadro-l__bottom face" />
  </div>
  <div class="cuadro-r">
    <a class="cuadro-r__front face" href="https://yyj.moe" target="_blank" />
    <div class="cuadro-r__back face" />
    <div class="cuadro-r__right face" />
    <div class="cuadro-r__left face" />
    <div class="cuadro-r__top face" />
    <div class="cuadro-r__bottom face" />
  </div>
</template>

<style lang="scss">
@use '~/assets/scss/3d-room/mixins' as *;
@use '~/assets/scss/3d-room/vars' as *;

.cuadro-l,
.cuadro-r {
  $width-el: 5vw;
  $height-el: 7vw;
  $depth-el: 0.125vw;

  @include cube($width-el, $height-el, $depth-el);
  position: absolute;
  left: 13vw;
  top: 1vw;
  width: 5vw;
  height: 0.5vw;

  transform: translateZ(10vw);

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
.cuadro-l {
  &__front {
    background-image: url('https://r2.yunyoujun.cn/images%2Fyun-alpha-compressed-small.webp');
    background-color: $cuadro-1;
    border: 1vw solid $cuadro-1;

    &::before {
      content: '';
      position: absolute;
      top: -1vw;
      left: -1vw;
      width: 5vw;
      height: 7vw;
      background-origin: padding-box;
      background-image: linear-gradient(
        to bottom,
        rgba($neon-2, 0.15),
        rgba($neon-2, 0.15)
      );
    }
  }
}
.cuadro-r {
  left: 20vw;
  &__front {
    background-image: url('https://r2.yunyoujun.cn/images%2Fyun-alpha-compressed-small.webp');
    background-color: $cuadro-2;
    border: 0.5vw solid $cuadro-2;
    &::before {
      content: '';
      position: absolute;
      top: -0.5vw;
      left: -0.5vw;
      width: 5vw;
      height: 7vw;
      background-origin: padding-box;
      background-image: linear-gradient(
        to bottom,
        rgba($neon-2, 0.15),
        rgba($neon-2, 0.15)
      );
    }
  }
}
</style>
