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
      <div class="face alt__front" />
      <div class="face alt__back" />
      <div class="face alt__right" />
      <div class="face alt__left" />
      <div class="face alt__top">
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
      <div class="face alt__bottom" />
    </div>
    <div class="alb">
      <div class="face alb__front" />
      <div class="face alb__back" />
      <div class="face alb__right" />
      <div class="face alb__left" />
      <div class="face alb__top" />
      <div class="face alb__bottom" />
    </div>
    <div class="arb">
      <div class="face arb__front" />
      <div class="face arb__back" />
      <div class="face arb__right" />
      <div class="face arb__left" />
      <div class="face arb__top" />
      <div class="face arb__bottom" />
    </div>
    <!-- --------------------- -->
    <YlfHouseWall />
    <!-- --------------------- -->
    <div class="puerta-c">
      <div class="puerta">
        <div class="face puerta__front" />
        <div class="face puerta__back" />
        <div class="face puerta__right" />
        <div class="face puerta__left" />
        <div class="face puerta__top" />
        <div class="face puerta__bottom" />
      </div>
      <div class="puerta-l">
        <div class="face puerta-l__front" />
        <div class="face puerta-l__back" />
        <div class="face puerta-l__right" />
        <div class="face puerta-l__left" />
        <div class="face puerta-l__top" />
        <div class="face puerta-l__bottom" />
      </div>
      <div class="puerta-r">
        <div class="face puerta-r__front" />
        <div class="face puerta-r__back" />
        <div class="face puerta-r__right" />
        <div class="face puerta-r__left" />
        <div class="face puerta-r__top" />
        <div class="face puerta-r__bottom" />
      </div>
      <div class="puerta-t">
        <div class="face puerta-t__front" />
        <div class="face puerta-t__back" />
        <div class="face puerta-t__right" />
        <div class="face puerta-t__left" />
        <div class="face puerta-t__top" />
        <div class="face puerta-t__bottom" />
      </div>
    </div>

    <YlfHouseAc />

    <YlfHousePainting />

    <div class="librero">
      <div class="face librero__front" />
      <div class="face librero__back" />
      <div class="face librero__right" />
      <div class="face librero__left" />
      <div class="face librero__top" />
      <div class="face librero__bottom" />
    </div>

    <div class="libros">
      <!-- Example with 6 books -->
      <div class="libro">
        <div class="face libro__front" />
        <div class="face libro__back" />
        <div class="face libro__right" />
        <div class="face libro__left" />
        <div class="face libro__top" />
        <div class="face libro__bottom" />
      </div>
      <!-- Repeat the above div for each book as needed -->
    </div>
    <div class="fotos">
      <!-- Example with 2 photos -->
      <div class="foto">
        <div class="face foto__front" />
        <div class="face foto__back" />
        <div class="face foto__right" />
        <div class="face foto__left" />
        <div class="face foto__top" />
        <div class="face foto__bottom" />
      </div>
      <!-- Repeat the above div for each photo as needed -->
    </div>
    <div class="cajas">
      <!-- Example with 3 boxes -->
      <div class="caja">
        <div class="face caja__front" />
        <div class="face caja__back" />
        <div class="face caja__right" />
        <div class="face caja__left" />
        <div class="face caja__top" />
        <div class="face caja__bottom" />
      </div>
      <!-- Repeat the above div for each box as needed -->
    </div>
    <YlfHouseTV />
    <div class="repisa-t">
      <div class="face repisa-t__front" />
      <div class="face repisa-t__back" />
      <div class="face repisa-t__right" />
      <div class="face repisa-t__left" />
      <div class="face repisa-t__top" />
      <div class="face repisa-t__bottom" />
    </div>
    <div class="repisa-b">
      <div class="face repisa-b__front" />
      <div class="face repisa-b__back" />
      <div class="face repisa-b__right" />
      <div class="face repisa-b__left" />
      <div class="face repisa-b__top" />
      <div class="face repisa-b__bottom" />
    </div>
    <div class="bocina-l">
      <div class="face bocina-l__front" />
      <div class="face bocina-l__back" />
      <div class="face bocina-l__right" />
      <div class="face bocina-l__left" />
      <div class="face bocina-l__top" />
      <div class="face bocina-l__bottom" />
    </div>
    <div class="bocina-r">
      <div class="face bocina-r__front" />
      <div class="face bocina-r__back" />
      <div class="face bocina-r__right" />
      <div class="face bocina-r__left" />
      <div class="face bocina-r__top" />
      <div class="face bocina-r__bottom" />
    </div>
    <div class="muro">
      <div class="face muro__front" />
      <div class="face muro__back" />
      <div class="face muro__right" />
      <div class="face muro__left" />
      <div class="face muro__top" />
      <div class="face muro__bottom" />
    </div>
    <div class="sillon-c">
      <div class="sillon-b">
        <div class="face sillon-b__front" />
        <div class="face sillon-b__back" />
        <div class="face sillon-b__right" />
        <div class="face sillon-b__left" />
        <div class="face sillon-b__top" />
        <div class="face sillon-b__bottom" />
      </div>
      <div class="sillon-t">
        <div class="face sillon-t__front" />
        <div class="face sillon-t__back" />
        <div class="face sillon-t__right" />
        <div the="sillon-t__left face" />
        <div class="face sillon-t__top" />
        <div class="face sillon-t__bottom" />
      </div>
      <div class="sillon-l">
        <div class="face sillon-l__front" />
        <div class="face sillon-l__back" />
        <div class="face sillon-l__right" />
        <div class="face sillon-l__left" />
        <div class="face sillon-l__top" />
        <div class="face sillon-l__bottom" />
      </div>
      <div class="sillon-r">
        <div class="face sillon-r__front" />
        <div class="face sillon-r__back" />
        <div class="face sillon-r__right" />
        <div class="face sillon-r__left" />
        <div the="sillon-r__top face" />
        <div class="face sillon-r__bottom" />
      </div>
    </div>
    <div class="mesa-c">
      <div class="mesa">
        <div class="face mesa__front" />
        <div class="face mesa__back" />
        <div class="face mesa__right" />
        <div class="mesa__right face" />
        <div class="face mesa__left" />
        <div class="face mesa__top" />
        <div class="face mesa__bottom" />
      </div>
      <!-- Example with 4 legs for the table -->
      <div class="mesa-p">
        <div class="face mesa-p__front" />
        <div class="face mesa-p__back" />
        <div class="face mesa-p__right" />
        <div class="face mesa-p__left" />
        <div class="face mesa-p__top" />
        <div class="face mesa-p__bottom" />
      </div>
      <!-- Repeat the above div for each leg as needed -->
      <div class="mesa-shadow" />
    </div>
    <div class="tablet">
      <div class="face tablet__front" />
      <div class="face tablet__back" />
      <div class="face tablet__right" />
      <div the="tablet__left face" />
      <div class="face tablet__top" />
      <div class="face tablet__bottom" />
    </div>
  </div>
</template>

<style lang="scss">
@use '~/assets/scss/3d-room/index.scss' as *;
</style>
