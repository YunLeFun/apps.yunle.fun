import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import { defineComponent, h } from 'vue'
import WorkshopPickerSheet from '../../app/components/workshop/PickerSheet.vue'

const containerStub = defineComponent({
  setup(_, { slots }) {
    return () => h('div', slots.default?.())
  },
})

const iconStub = defineComponent({
  setup() {
    return () => h('span')
  },
})

const ionicStubs = {
  IonButton: containerStub,
  IonButtons: containerStub,
  IonContent: containerStub,
  IonHeader: containerStub,
  IonIcon: iconStub,
  IonModal: containerStub,
  IonSearchbar: containerStub,
  IonTitle: containerStub,
  IonToolbar: containerStub,
}

describe('workshop picker sheet', () => {
  it('does not describe an anonymous session as having no joined workshops', () => {
    const wrapper = mount(WorkshopPickerSheet as any, {
      props: {
        isOpen: true,
        currentScope: 'public',
        workshops: [],
        isLoggedIn: false,
      },
      global: {
        stubs: ionicStubs,
      },
    })

    expect(wrapper.text()).toContain('登录后查看个人工坊')
    expect(wrapper.text()).not.toContain('还没有加入个人工坊')
  })

  it('keeps the joined-workshop empty state for a logged-in account', () => {
    const wrapper = mount(WorkshopPickerSheet, {
      props: {
        isOpen: true,
        currentScope: 'public',
        workshops: [],
        isLoggedIn: true,
      },
      global: {
        stubs: ionicStubs,
      },
    })

    expect(wrapper.text()).toContain('还没有加入个人工坊')
    expect(wrapper.text()).not.toContain('登录后查看个人工坊')
    expect(wrapper.text()).toContain('开启工坊')
    expect(wrapper.text()).not.toContain('管理工坊')
  })

  it('renders an active workshop returned for the logged-in account', () => {
    const wrapper = mount(WorkshopPickerSheet, {
      props: {
        isOpen: true,
        currentScope: 'public',
        isLoggedIn: true,
        workshops: [{
          _id: '6MU9AG',
          ownerName: '云乐坊',
          name: '云乐坊内部工坊',
          description: '云乐坊内部应用与运营工具，仅坊主及坊客可见',
          joinPolicy: 'approval',
          status: 'active',
        }],
      },
      global: {
        stubs: ionicStubs,
      },
    })

    expect(wrapper.text()).toContain('云乐坊内部工坊')
    expect(wrapper.text()).toContain('云乐坊的工坊')
    expect(wrapper.text()).toContain('全部动态')
  })

  it('keeps the manage label when the account owns a workshop', () => {
    const wrapper = mount(WorkshopPickerSheet, {
      props: {
        isOpen: true,
        currentScope: '6MU9AG',
        isLoggedIn: true,
        ownedWorkshopId: '6MU9AG',
        workshops: [{
          _id: '6MU9AG',
          ownerName: '云乐坊',
          name: '云乐坊内部工坊',
          description: '内部应用',
          joinPolicy: 'approval',
          status: 'active',
        }],
      },
      global: {
        stubs: ionicStubs,
      },
    })

    expect(wrapper.text()).toContain('管理工坊')
    expect(wrapper.text()).not.toContain('开启工坊')
  })
})
