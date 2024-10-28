<script setup lang="ts">
const { data } = await useFetch('/api/wx/user')

watch(() => data.value, () => {
  userInfo.value.avatar = data.value?.headimgurl || ''
  userInfo.value.nickname = data.value?.nickname || '无名氏'
}, {
  immediate: true,
})
</script>

<template>
  <Card class="m-auto mt-20 max-w-3xl">
    <template #content>
      <Tabs value="0">
        <TabList>
          <Tab value="0">
            个人信息
          </Tab>
          <Tab value="1">
            关联应用
          </Tab>
        </TabList>
        <TabPanels>
          <TabPanel value="0">
            <div flex="~ col" class="mt-4 items-center justify-center gap-4">
              <Avatar
                :image="userInfo.avatar"
                size="xlarge"
                shape="circle"
              />

              <div>
                {{ userInfo.nickname }}
              </div>
            </div>
          </TabPanel>
          <TabPanel value="1">
            <AppList />
          </TabPanel>
        </TabPanels>
      </Tabs>
    </template>
  </Card>
</template>
