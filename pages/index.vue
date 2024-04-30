<script lang="ts" setup>
definePageMeta({
  layout: 'home',
})

const houseRef = ref<HTMLElement | null>(null)

/*
  Designed by: Jarlan Perez
  Original image: https://www.artstation.com/artwork/VdBllN

  Modified by: YunYouJun
*/
useEventListener(document, 'pointermove', (e) => {
  const x = e.pageX / window.innerWidth - 0.5
  const y = e.pageY / window.innerHeight - 0.5

  if (!houseRef.value)
    return
  houseRef.value.style.transform = `
        perspective(90vw)
        rotateX(${-y * 4 + 75}deg)
        rotateZ(${-x * 12 + 45}deg)
        translateZ(-9vw)
    `
})
</script>

<template>
  <div id="h" ref="houseRef" class="house">
    <div class="h-lights">
      <div class="h-light" />
      <div class="h-light" />
      <div class="h-light" />
      <div class="h-light" />
      <div class="h-light" />
      <div class="h-light" />
    </div>
    <div class="h-shadow" />
    <!-- --------------------- -->
    <div class="alt">
      <div class="alt__front face" />
      <div class="alt__back face" />
      <div class="alt__right face" />
      <div class="alt__left face" />
      <div class="alt__top face">
        <div class="light" />
        <div class="light" />
        <div class="light" />
        <div class="light" />
        <div class="light" />
        <div class="light" />
        <div class="light" />
        <div class="light" />
        <div class="light" />
      </div>
      <div class="alt__bottom face" />
    </div>
    <div class="alb">
      <div class="alb__front face" />
      <div class="alb__back face" />
      <div class="alb__right face" />
      <div class="alb__left face" />
      <div class="alb__top face" />
      <div class="alb__bottom face" />
    </div>
    <div class="arb">
      <div class="arb__front face" />
      <div class="arb__back face" />
      <div class="arb__right face" />
      <div class="arb__left face" />
      <div class="arb__top face" />
      <div class="arb__bottom face" />
    </div>
    <!-- --------------------- -->
    <YlfHouseWall />
    <!-- --------------------- -->
    <div class="puerta-c">
      <div class="puerta">
        <div class="puerta__front face" />
        <div class="puerta__back face" />
        <div class="puerta__right face" />
        <div class="puerta__left face" />
        <div class="puerta__top face" />
        <div class="puerta__bottom face" />
      </div>
      <div class="puerta-l">
        <div class="puerta-l__front face" />
        <div class="puerta-l__back face" />
        <div class="puerta-l__right face" />
        <div class="puerta-l__left face" />
        <div class="puerta-l__top face" />
        <div class="puerta-l__bottom face" />
      </div>
      <div class="puerta-r">
        <div class="puerta-r__front face" />
        <div class="puerta-r__back face" />
        <div class="puerta-r__right face" />
        <div class="puerta-r__left face" />
        <div class="puerta-r__top face" />
        <div class="puerta-r__bottom face" />
      </div>
      <div class="puerta-t">
        <div class="puerta-t__front face" />
        <div class="puerta-t__back face" />
        <div class="puerta-t__right face" />
        <div class="puerta-t__left face" />
        <div class="puerta-t__top face" />
        <div class="puerta-t__bottom face" />
      </div>
    </div>

    <YlfHouseAc />

    <YlfHousePainting />

    <div class="librero">
      <div class="librero__front face" />
      <div class="librero__back face" />
      <div class="librero__right face" />
      <div class="librero__left face" />
      <div class="librero__top face" />
      <div class="librero__bottom face" />
    </div>

    <div class="libros">
      <!-- Example with 6 books -->
      <div class="libro">
        <div class="libro__front face" />
        <div class="libro__back face" />
        <div class="libro__right face" />
        <div class="libro__left face" />
        <div class="libro__top face" />
        <div class="libro__bottom face" />
      </div>
      <!-- Repeat the above div for each book as needed -->
    </div>
    <div class="fotos">
      <!-- Example with 2 photos -->
      <div class="foto">
        <div class="foto__front face" />
        <div class="foto__back face" />
        <div class="foto__right face" />
        <div class="foto__left face" />
        <div class="foto__top face" />
        <div class="foto__bottom face" />
      </div>
      <!-- Repeat the above div for each photo as needed -->
    </div>
    <div class="cajas">
      <!-- Example with 3 boxes -->
      <div class="caja">
        <div class="caja__front face" />
        <div class="caja__back face" />
        <div class="caja__right face" />
        <div class="caja__left face" />
        <div class="caja__top face" />
        <div class="caja__bottom face" />
      </div>
      <!-- Repeat the above div for each box as needed -->
    </div>
    <YlfHouseTV />
    <div class="repisa-t">
      <div class="repisa-t__front face" />
      <div class="repisa-t__back face" />
      <div class="repisa-t__right face" />
      <div class="repisa-t__left face" />
      <div class="repisa-t__top face" />
      <div class="repisa-t__bottom face" />
    </div>
    <div class="repisa-b">
      <div class="repisa-b__front face" />
      <div class="repisa-b__back face" />
      <div class="repisa-b__right face" />
      <div class="repisa-b__left face" />
      <div class="repisa-b__top face" />
      <div class="repisa-b__bottom face" />
    </div>
    <div class="bocina-l">
      <div class="bocina-l__front face" />
      <div class="bocina-l__back face" />
      <div class="bocina-l__right face" />
      <div class="bocina-l__left face" />
      <div class="bocina-l__top face" />
      <div class="bocina-l__bottom face" />
    </div>
    <div class="bocina-r">
      <div class="bocina-r__front face" />
      <div class="bocina-r__back face" />
      <div class="bocina-r__right face" />
      <div class="bocina-r__left face" />
      <div class="bocina-r__top face" />
      <div class="bocina-r__bottom face" />
    </div>
    <div class="muro">
      <div class="muro__front face" />
      <div class="muro__back face" />
      <div class="muro__right face" />
      <div class="muro__left face" />
      <div class="muro__top face" />
      <div class="muro__bottom face" />
    </div>
    <div class="sillon-c">
      <div class="sillon-b">
        <div class="sillon-b__front face" />
        <div class="sillon-b__back face" />
        <div class="sillon-b__right face" />
        <div class="sillon-b__left face" />
        <div class="sillon-b__top face" />
        <div class="sillon-b__bottom face" />
      </div>
      <div class="sillon-t">
        <div class="sillon-t__front face" />
        <div class="sillon-t__back face" />
        <div class="sillon-t__right face" />
        <div the="sillon-t__left face" />
        <div class="sillon-t__top face" />
        <div class="sillon-t__bottom face" />
      </div>
      <div class="sillon-l">
        <div class="sillon-l__front face" />
        <div class="sillon-l__back face" />
        <div class="sillon-l__right face" />
        <div class="sillon-l__left face" />
        <div class="sillon-l__top face" />
        <div class="sillon-l__bottom face" />
      </div>
      <div class="sillon-r">
        <div class="sillon-r__front face" />
        <div class="sillon-r__back face" />
        <div class="sillon-r__right face" />
        <div class="sillon-r__left face" />
        <div the="sillon-r__top face" />
        <div class="sillon-r__bottom face" />
      </div>
    </div>
    <div class="mesa-c">
      <div class="mesa">
        <div class="mesa__front face" />
        <div class="mesa__back face" />
        <div class="mesa__right face" />
        <div class="mesa__right face" />
        <div class="mesa__left face" />
        <div class="mesa__top face" />
        <div class="mesa__bottom face" />
      </div>
      <!-- Example with 4 legs for the table -->
      <div class="mesa-p">
        <div class="mesa-p__front face" />
        <div class="mesa-p__back face" />
        <div class="mesa-p__right face" />
        <div class="mesa-p__left face" />
        <div class="mesa-p__top face" />
        <div class="mesa-p__bottom face" />
      </div>
      <!-- Repeat the above div for each leg as needed -->
      <div class="mesa-shadow" />
    </div>
    <div class="tablet">
      <div class="tablet__front face" />
      <div class="tablet__back face" />
      <div class="tablet__right face" />
      <div the="tablet__left face" />
      <div class="tablet__top face" />
      <div class="tablet__bottom face" />
    </div>
  </div>
</template>

<style lang="scss">
@use '~/assets/scss/3d-room/index.scss' as *;
</style>
