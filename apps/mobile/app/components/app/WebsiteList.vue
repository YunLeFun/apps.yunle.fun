<script setup lang="ts">
import {
  kBlockTitle,
  kList,
  kListItem,
} from 'konsta/vue'
import { YLF_WEBSITES } from '~/constants'

function openLink(url: string) {
  if (!url)
    return
  window.open(url, '_blank')
}
</script>

<template>
  <k-block-title>官方网站</k-block-title>
  <k-list strong inset>
    <k-list-item
      v-for="item in YLF_WEBSITES"
      :key="item.label"
      link
      :title="item.label"
      :after="item.domain"
      @click="openLink(item.url)"
    >
      <template #media>
        <span
          class="ios-icon-box"
          :style="{ backgroundColor: item.color }"
        >
          <Icon :name="item.icon" class="text-white" size="18px" />
        </span>
      </template>
    </k-list-item>
  </k-list>
</template>
