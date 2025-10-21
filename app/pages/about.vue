<script setup lang="ts">
import { YLF_LINKS } from '~/constants'
</script>

<template>
  <ion-page>
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start">
          <ion-back-button default-href="/my" />
        </ion-buttons>
        <ion-title>关于</ion-title>
      </ion-toolbar>
    </ion-header>

    <ion-content>
      <TheAboutList />

      <ion-list :inset="true">
        <ion-item :href="YLF_LINKS.studio.url" target="_blank">
          <ion-icon slot="start" :icon="ioniconsCloud" />
          <ion-label>{{ YLF_LINKS.studio.label }}</ion-label>
          <ion-text>{{ YLF_LINKS.studio.text }}</ion-text>
        </ion-item>
      </ion-list>
    </ion-content>
  </ion-page>
</template>
