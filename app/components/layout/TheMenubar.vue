<script setup lang="ts">
import { ref } from 'vue'

const items = ref([
  {
    label: '主页',
    icon: 'i-ri-home-line',
    route: '/',
  },
  {
    label: '项目',
    icon: 'i-ri-apps-line',
    items: [
      {
        label: 'TODO',
        icon: 'i-ri-todo-line',
        route: '/todo',
      },
      {
        label: 'UI Design',
        icon: 'i-ri-artboard-line',
      },
    ],
  },
  {
    label: '工作室',
    icon: 'i-ri-building-2-line',
    href: 'https://studio.yunle.fun',
    target: '_blank',
  },
])

const { loggedIn } = useUserSession()

// ClientOnly for first show in mobile
</script>

<template>
  <ClientOnly>
    <Transition appear>
      <div class="fixed left-4 right-4 top-4 z-1">
        <Menubar :model="items" class="rounded-3rem!">
          <template #item="{ item, props, hasSubmenu }">
            <router-link v-if="item.route" v-slot="{ href, navigate }" :to="item.route" custom>
              <a v-ripple :href="href" v-bind="props.action" @click="navigate">
                <span :class="item.icon" />
                <span>{{ item.label }}</span>
              </a>
            </router-link>
            <a v-else v-ripple :href="item.href" :target="item.target" v-bind="props.action">
              <span :class="item.icon" />
              <span>{{ item.label }}</span>
              <!-- <span v-if="hasSubmenu" class="pi pi-fw pi-angle-down" /> -->
              <span v-if="hasSubmenu" class="i-ri-arrow-down-s-line" />
            </a>
          </template>

          <template #end>
            <div class="flex items-center gap-2 pr-2">
              <!-- <InputText placeholder="Search" type="text" class="w-32 sm:w-auto" /> -->
              <!-- <Avatar image="/images/avatar/amyelsner.png" shape="circle" /> -->

              <div
                v-if="!loggedIn"
                class="p-menubar-item"
              >
                <div class="p-menubar-item-content">
                  <RouterLink
                    to="/login"
                    class="p-menubar-item-link inline-flex items-center justify-center gap-2 rounded"
                  >
                    <div class="i-ri-login-circle-line" /> 登录
                  </RouterLink>
                </div>
              </div>

              <div
                v-else
                class="p-menubar-item"
              >
                <Avatar
                  :image="userInfo?.avatar"
                  :label="userInfo?.nickname.slice(0, 1)"
                  shape="circle"
                />
              </div>
            </div>
          </template>
        </Menubar>
      </div>
    </Transition>
  </ClientOnly>
</template>
