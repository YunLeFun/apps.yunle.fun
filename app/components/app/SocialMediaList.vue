<script setup lang="ts">
import {
  kBlockTitle,
  kList,
  kListItem,
} from 'konsta/vue'
import { actionSheetController } from '@ionic/vue'
import { YLF_SOCIAL_MEDIA } from '~/constants'

const toast = useToast()

type SocialItem = typeof YLF_SOCIAL_MEDIA[number]

function openLink(url: string) {
  if (!url) return
  window.open(url, '_blank')
}

async function handleItemClick(item: SocialItem) {
  if ('wxOfficialName' in item && item.wxOfficialName) {
    const actionSheet = await actionSheetController.create({
      header: `微信公众号：${item.wxOfficialName}`,
      buttons: [
        {
          text: '复制公众号名称',
          handler: async () => {
            try {
              await navigator.clipboard.writeText(item.wxOfficialName as string)
              toast.showSuccess('已复制，请在微信中搜索关注')
            }
            catch {
              toast.showError('复制失败')
            }
          },
        },
        { text: '取消', role: 'cancel' },
      ],
    })
    await actionSheet.present()
    return
  }
  openLink(item.url)
}
</script>

<template>
  <k-block-title>社交媒体</k-block-title>
  <k-list strong inset>
    <k-list-item
      v-for="item in YLF_SOCIAL_MEDIA"
      :key="item.label"
      link
      :title="item.label"
      :after="item.handle"
      @click="handleItemClick(item)"
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
