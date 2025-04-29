<script lang="ts" setup>
import DataView from 'primevue/dataview'
import Tag from 'primevue/tag'

const products = ref<{
  id: string
  code: string
  name: string
  description: string
  image: string
  price: number
  category: string
  quantity: number
  inventoryStatus: 'INSTOCK' | 'LOWSTOCK' | 'OUTOFSTOCK'
  rating: number
  dataKey: string
}[]>([
  {
    id: '1000',
    code: 'f230fh0g3',
    name: 'Bamboo Watch',
    description: 'Product Description',
    image: 'bamboo-watch.jpg',
    price: 65,
    category: 'Accessories',
    quantity: 24,
    inventoryStatus: 'INSTOCK',
    rating: 5,
    dataKey: '1',
  },
  {
    id: '1000',
    code: 'f230fh0g3',
    name: 'Bamboo Watch',
    description: 'Product Description',
    image: 'bamboo-watch.jpg',
    price: 65,
    category: 'Accessories',
    quantity: 24,
    inventoryStatus: 'INSTOCK',
    rating: 5,
    dataKey: '2',
  },
  {
    id: '1000',
    code: 'f230fh0g3',
    name: 'Bamboo Watch',
    description: 'Product Description',
    image: 'bamboo-watch.jpg',
    price: 65,
    category: 'Accessories',
    quantity: 24,
    inventoryStatus: 'INSTOCK',
    rating: 5,
    dataKey: '3',
  },
])

function getSeverity(product: {
  inventoryStatus: 'INSTOCK' | 'LOWSTOCK' | 'OUTOFSTOCK'
}): 'success' | 'warn' | 'danger' | 'info' {
  switch (product.inventoryStatus) {
    case 'INSTOCK':
      return 'success'

    case 'LOWSTOCK':
      return 'warn'

    case 'OUTOFSTOCK':
      return 'danger'

    default:
      return 'info'
  }
}
</script>

<template>
  <div class="card">
    <DataView :value="products" data-key="custom">
      <template #list="slotProps">
        <div class="flex flex-col">
          <div v-for="(item, index) in slotProps.items" :key="index">
            <div class="flex flex-col gap-4 p-6 sm:flex-row sm:items-center" :class="{ 'border-t border-surface-200 dark:border-surface-700': index !== 0 }">
              <div class="relative md:w-40">
                <img class="mx-auto block w-full rounded xl:block" :src="`https://primefaces.org/cdn/primevue/images/product/${item.image}`" :alt="item.name">
                <div class="rounded-border absolute bg-black/70" style="left: 4px; top: 4px">
                  <Tag :value="item.inventoryStatus" :severity="getSeverity(item)" />
                </div>
              </div>
              <div class="flex flex-1 flex-col justify-between gap-6 md:flex-row md:items-center">
                <div class="flex flex-row items-start justify-between gap-2 md:flex-col">
                  <div>
                    <span class="text-surface-500 dark:text-surface-400 text-sm font-medium">{{ item.category }}</span>
                    <div class="mt-2 text-lg font-medium">
                      {{ item.name }}
                    </div>
                  </div>
                  <div class="bg-surface-100 p-1" style="border-radius: 30px">
                    <div class="bg-surface-0 flex items-center justify-center gap-2 px-2 py-1" style="border-radius: 30px; box-shadow: 0px 1px 2px 0px rgba(0, 0, 0, 0.04), 0px 1px 2px 0px rgba(0, 0, 0, 0.06)">
                      <span class="text-surface-900 text-sm font-medium">{{ item.rating }}</span>
                      <i class="pi pi-star-fill text-yellow-500" />
                    </div>
                  </div>
                </div>
                <div class="flex flex-col gap-8 md:items-end">
                  <span class="text-xl font-semibold">${{ item.price }}</span>
                  <div class="flex flex-row-reverse gap-2 md:flex-row">
                    <Button icon="pi pi-heart" outlined />
                    <Button icon="pi pi-shopping-cart" label="Buy Now" :disabled="item.inventoryStatus === 'OUTOFSTOCK'" class="flex-auto whitespace-nowrap md:flex-initial" />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </template>
    </DataView>
  </div>
</template>
