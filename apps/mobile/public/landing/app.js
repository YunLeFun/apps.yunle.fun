(function () {
  'use strict'

  const webAppPath = '/tabs/home'
  const webEntryKey = 'ylf:web-entry'
  const standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true
  const showcaseRequested = new URLSearchParams(window.location.search).has('showcase')
  let rememberedWebEntry = false
  try {
    rememberedWebEntry = localStorage.getItem(webEntryKey) === 'app'
  }
  catch {}

  if (standalone || (!showcaseRequested && rememberedWebEntry)) {
    window.location.replace(webAppPath)
    return
  }

  document.querySelectorAll(`a[href="${webAppPath}"]`).forEach((link) => {
    link.addEventListener('click', () => {
      try {
        localStorage.setItem(webEntryKey, 'app')
      }
      catch {}
    })
  })

  // 标记脚本已就绪，确保无脚本时所有内容与真实链接保持可见可用
  document.documentElement.classList.add('js-ready')

  /* ========================================================================
     1. 动效偏好管理（系统 prefers-reduced-motion + 页面手动切换）
     ======================================================================== */
  const mediaReduced = window.matchMedia('(prefers-reduced-motion: reduce)')
  let userReduced = null // null = 跟随系统
  const motionToggle = document.getElementById('motionToggle')

  function isReducedMotion() {
    return userReduced !== null ? userReduced : mediaReduced.matches
  }

  function syncMotionUI() {
    const reduced = isReducedMotion()
    if (reduced) {
      document.documentElement.setAttribute('data-motion', 'reduced')
    }
    else {
      document.documentElement.removeAttribute('data-motion')
    }
    if (motionToggle) {
      motionToggle.setAttribute('aria-pressed', String(reduced))
      const label = motionToggle.querySelector('.motion-label')
      if (label) {
        label.textContent = reduced ? '动效减' : '动效开'
      }
      motionToggle.title = reduced ? '当前为减少动态效果，点击开启完整动效' : '当前已开启完整动效，点击切换为减少动态效果'
    }
  }

  if (motionToggle) {
    motionToggle.addEventListener('click', () => {
      userReduced = !isReducedMotion()
      syncMotionUI()
    })
  }

  if (mediaReduced.addEventListener) {
    mediaReduced.addEventListener('change', () => {
      if (userReduced === null)
        syncMotionUI()
    })
  }
  syncMotionUI()

  /* ========================================================================
     2. 云应用数据与微型交互预览（「轻点即开」）
     ======================================================================== */
  const APP_CATALOG = {
    couplet: {
      id: 'couplet',
      name: 'AI 春联',
      subtitle: '随手写一副应景春联',
      iconClass: 'icon-couplet',
      iconHtml: '<span class="couplet-char">春</span>',
    },
    ac: {
      id: 'ac',
      name: '云空调',
      subtitle: '毫无制冷效果的便携小空调',
      iconClass: 'icon-ac',
      iconHtml:
        '<svg viewBox="0 0 36 36" width="26" height="26" fill="none">'
        + '<path d="M18 5v26M5 18h26M8.8 8.8l18.4 18.4M27.2 8.8L8.8 27.2" stroke="#38BDF8" stroke-width="2.6" stroke-linecap="round"/>'
        + '<circle cx="18" cy="18" r="3.5" fill="#E0F2FE" stroke="#0284C7" stroke-width="2"/>'
        + '</svg>',
    },
    pinball: {
      id: 'pinball',
      name: '云乐弹珠',
      subtitle: '仿真 2.5D 弹珠机 · 拉杆开彩',
      iconClass: 'icon-pinball',
      iconHtml:
        '<svg viewBox="0 0 36 36" width="26" height="26" fill="none">'
        + '<rect x="6" y="4" width="24" height="28" rx="6" fill="#fff" fill-opacity="0.92"/>'
        + '<circle cx="20" cy="12" r="3" fill="#F59E0B"/>'
        + '<circle cx="14" cy="18" r="2.2" fill="#3B82F6"/>'
        + '<path d="M11 26h4v3h-4zM16 26h4v3h-4zM21 26h4v3h-4z" fill="#EF4444"/>'
        + '<path d="M26 22v7" stroke="#EC4899" stroke-width="2.4" stroke-linecap="round"/>'
        + '</svg>',
    },
    starplane: {
      id: 'starplane',
      name: '星纸',
      subtitle: '纸飞机穿越星球与虫洞',
      iconClass: 'icon-starplane',
      iconHtml:
        '<svg viewBox="0 0 36 36" width="26" height="26" fill="none">'
        + '<path d="M6 19l23-10-8 21-4.5-7.5L6 19z" fill="#38BDF8" stroke="#0369A1" stroke-width="1.8" stroke-linejoin="round"/>'
        + '<path d="M29 9L16.5 22.5" stroke="#E0F2FE" stroke-width="1.8" stroke-linecap="round"/>'
        + '</svg>',
    },
    fc: {
      id: 'fc',
      name: 'FC 红白机',
      subtitle: '即开即玩 · 怀旧像素掌机',
      iconClass: 'icon-fc',
      iconHtml:
        '<svg viewBox="0 0 36 36" width="26" height="26" fill="none">'
        + '<rect x="4" y="10" width="28" height="16" rx="6" fill="#334155"/>'
        + '<path d="M11 15v6M8 18h6" stroke="#E2E8F0" stroke-width="2.2" stroke-linecap="round"/>'
        + '<circle cx="22.5" cy="19.5" r="2" fill="#EF4444"/>'
        + '<circle cx="26.5" cy="16.5" r="2" fill="#F59E0B"/>'
        + '</svg>',
    },
  }

  /* ========================================================================
     3. 首屏收纳状态与飞入动效
     ======================================================================== */
  const dockSlots = [null, null, null, null]
  let replaceCursor = 0
  let isFlying = false
  let toastTimer = null

  const collectionSlots = document.getElementById('collectionSlots')
  const slotButtons = Array.from(collectionSlots.querySelectorAll('.dock-slot'))
  const siteHeader = document.querySelector('.site-header')
  const dockCounter = document.getElementById('dockCounter')
  const dockLiveHint = document.getElementById('dockLiveHint')
  const phoneToast = document.getElementById('phoneToast')
  const phoneToastText = document.getElementById('phoneToastText')
  const flightLayer = document.getElementById('flightLayer')
  const cartridgeRack = document.getElementById('cartridgeRack')

  const miniAppSheet = document.getElementById('miniAppSheet')
  const miniAppBadge = document.getElementById('miniAppBadge')
  const miniAppTitle = document.getElementById('miniAppTitle')
  const miniAppSubtitle = document.getElementById('miniAppSubtitle')
  const miniAppBody = document.getElementById('miniAppBody')
  const miniAppClose = document.getElementById('miniAppClose')

  function showPhoneToast(msg) {
    if (!phoneToast || !phoneToastText)
      return
    phoneToastText.textContent = msg
    phoneToast.hidden = false
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => {
      phoneToast.hidden = true
    }, 2400)
  }

  function renderDockUI(justLandedIndex) {
    let filledCount = 0

    slotButtons.forEach((btn, idx) => {
      const appId = dockSlots[idx]
      btn.classList.remove('just-landed')
      if (appId && APP_CATALOG[appId]) {
        filledCount += 1
        const app = APP_CATALOG[appId]
        btn.classList.add('is-filled')
        btn.classList.remove('is-empty')
        btn.setAttribute('data-app-id', appId)
        btn.disabled = false
        btn.setAttribute('aria-label', `打开${app.name}`)
        btn.innerHTML = `<span class="dock-tile ${app.iconClass}">${app.iconHtml}</span>`
        if (idx === justLandedIndex && !isReducedMotion()) {
          void btn.offsetWidth
          btn.classList.add('just-landed')
        }
      }
      else {
        btn.classList.remove('is-filled')
        btn.classList.add('is-empty')
        btn.removeAttribute('data-app-id')
        btn.disabled = true
        btn.setAttribute('aria-label', `空位 ${idx + 1}`)
        btn.innerHTML = '<span class="dock-placeholder" aria-hidden="true">+</span>'
      }
    })

    if (dockCounter) {
      dockCounter.textContent = `已收纳 ${filledCount} / 4`
    }

    // 同步左侧卡带芯片状态
    if (cartridgeRack) {
      const chips = cartridgeRack.querySelectorAll('.cartridge-chip')
      chips.forEach((chip) => {
        const id = chip.getAttribute('data-app-id')
        const docked = dockSlots.includes(id)
        chip.classList.toggle('is-docked', docked)
        const name = APP_CATALOG[id].name
        chip.setAttribute('aria-label', docked ? `打开${name}` : `将${name}收进云居`)
        const pill = chip.querySelector('.chip-action-pill')
        if (pill) {
          pill.textContent = docked ? '▶ 轻点即开' : '+ 收进云居'
        }
      })
    }
  }

  function findTargetSlotIndex() {
    const emptyIdx = dockSlots.indexOf(null)
    if (emptyIdx !== -1)
      return emptyIdx
    const target = replaceCursor
    replaceCursor = (replaceCursor + 1) % dockSlots.length
    return target
  }

  function visibleStage() {
    const viewport = window.visualViewport
    const viewportTop = viewport?.offsetTop ?? 0
    return {
      top: Math.max(viewportTop, siteHeader.getBoundingClientRect().bottom),
      bottom: viewportTop + (viewport?.height ?? window.innerHeight),
    }
  }

  function revealStage(source, target) {
    const { top, bottom } = visibleStage()
    const targetRect = target.getBoundingClientRect()
    const sourceRect = source?.getBoundingClientRect() ?? targetRect
    const first = Math.min(sourceRect.top, targetRect.top) - 24
    const last = Math.max(sourceRect.bottom, targetRect.bottom) + 24
    let offset = 0

    if (targetRect.height + 48 > bottom - top) {
      offset = targetRect.top - top - 24
    }
    else if (last - first > bottom - top) {
      // On very short screens, prioritize the destination.
      offset = targetRect.bottom > bottom ? targetRect.bottom - bottom + 24 : targetRect.top - top - 24
    }
    else if (first < top) {
      offset = first - top
    }
    else if (last > bottom) {
      offset = last - bottom
    }

    if (offset)
      window.scrollBy({ top: offset, behavior: 'instant' })
  }

  function flyToDock(appId, sourceEl, onComplete) {
    const app = APP_CATALOG[appId]
    if (!app || isFlying)
      return

    const targetIdx = findTargetSlotIndex()
    const target = slotButtons[targetIdx]
    isFlying = true
    revealStage(sourceEl, target)

    function land() {
      dockSlots[targetIdx] = appId
      renderDockUI(targetIdx)
      showPhoneToast(`已将「${app.name}」收进云居`)
      dockLiveHint.textContent = `再点「${app.name}」，即可打开`
      isFlying = false
      onComplete?.()
    }

    if (isReducedMotion() || !sourceEl) {
      land()
      return
    }

    // Measure after the view has moved, so the flight starts and lands in view.
    requestAnimationFrame(() => {
      const startRect = sourceEl.getBoundingClientRect()
      const endRect = target.getBoundingClientRect()
      const { top, bottom } = visibleStage()
      const size = 44
      const startX = startRect.left + (startRect.width - size) / 2
      const startY = Math.max(top, Math.min(bottom - size, startRect.top + (startRect.height - size) / 2))
      const endX = endRect.left + (endRect.width - size) / 2
      const endY = endRect.top + (endRect.height - size) / 2
      const arcX = (startX + endX) / 2
      const arcY = Math.max(top + 4, Math.min(startY, endY) - Math.max(50, Math.abs(endX - startX) * 0.22))
      const flyer = document.createElement('div')
      flyer.className = `flying-tile ${app.iconClass}`
      flyer.innerHTML = app.iconHtml
      flightLayer.appendChild(flyer)

      let startedAt
      function step(timestamp) {
        startedAt ??= timestamp
        const progress = Math.min(1, (timestamp - startedAt) / 560)
        const t = 1 - (1 - progress) ** 3
        const remaining = 1 - t
        const x = remaining ** 2 * startX + 2 * remaining * t * arcX + t ** 2 * endX
        const y = remaining ** 2 * startY + 2 * remaining * t * arcY + t ** 2 * endY
        const bounce = Math.sin(progress * Math.PI)
        const scale = 1 + bounce * 0.28 - progress * 0.08
        flyer.style.transform = `translate3d(${x}px, ${y}px, 0) scale(${scale}) rotate(${bounce * 12}deg)`

        if (progress < 1 && !isReducedMotion()) {
          requestAnimationFrame(step)
        }
        else {
          flyer.remove()
          land()
        }
      }

      step(performance.now())
    })
  }

  /* ========================================================================
     4. 手机内「轻点即开」微体验渲染器
     ======================================================================== */
  const miniState = {
    acOn: true,
    acTemp: 24,
    pinballScore: 0,
    planeDist: 120,
    fcScore: 1983,
    coupletIdx: 0,
  }

  const COUPLETS = [
    { top: '轻云常乐', a: '上联：一匣云居藏百器', b: '下联：轻点方寸尽欢颜' },
    { top: '码到成功', a: '上联：工坊寻得称手物', b: '下联：掌上常留顺心风' },
    { top: '岁岁安闲', a: '上联：不占清屏三寸地', b: '下联：常开好梦满窗云' },
  ]

  function renderMiniAppContent(appId) {
    if (!miniAppBody)
      return

    if (appId === 'ac') {
      miniAppBody.innerHTML
        = `<div class="mini-card">`
          + `  <div class="ac-unit">`
          + `    <div class="ac-led ${miniState.acOn ? '' : 'is-off'}" id="acLed">${
            miniState.acOn ? `${miniState.acTemp}°C` : 'OFF'
          }    </div>`
          + `    <div class="ac-vent ${miniState.acOn ? 'is-on' : ''}"></div>`
          + `  </div>`
          + `  <div class="mini-btn-row">`
          + `    <button type="button" class="mini-ctrl-btn" data-ac="down">- 降温</button>`
          + `    <button type="button" class="mini-ctrl-btn is-primary" data-ac="power">${miniState.acOn ? '关机' : '开机'}</button>`
          + `    <button type="button" class="mini-ctrl-btn" data-ac="up">+ 升温</button>`
          + `  </div>`
          + `  <p class="mini-status-note">${
            miniState.acOn ? '呼呼送风中 · 毫无制冷效果，但心静自然凉' : '空调已待机 · 点开机吹一口心理凉风'
          }  </p>`
          + `</div>`

      miniAppBody.querySelectorAll('[data-ac]').forEach((btn) => {
        btn.addEventListener('click', () => {
          const act = btn.getAttribute('data-ac')
          if (act === 'power')
            miniState.acOn = !miniState.acOn
          if (act === 'down' && miniState.acOn)
            miniState.acTemp = Math.max(16, miniState.acTemp - 1)
          if (act === 'up' && miniState.acOn)
            miniState.acTemp = Math.min(30, miniState.acTemp + 1)
          renderMiniAppContent('ac')
        })
      })
      return
    }

    if (appId === 'pinball') {
      miniAppBody.innerHTML
        = `<div class="pinball-board">`
          + `  <div style="display:flex;justify-content:space-between;align-items:center;">`
          + `    <span style="font-size:11px;opacity:.85;">CLOUD PINBALL</span>`
          + `    <span class="pinball-score" id="pbScore">${miniState.pinballScore}</span>`
          + `  </div>`
          + `  <span class="pinball-ball" id="pbBall"></span>`
          + `  <span style="font-size:11px;opacity:.9;" id="pbMsg">拉动发射杆，冲向高倍率口</span>`
          + `</div>`
          + `<div class="mini-btn-row">`
          + `  <button type="button" class="mini-ctrl-btn is-primary" id="pbLaunch">拉杆发射 ◉</button>`
          + `</div>`

      const pbLaunch = document.getElementById('pbLaunch')
      const pbBall = document.getElementById('pbBall')
      const pbScore = document.getElementById('pbScore')
      const pbMsg = document.getElementById('pbMsg')
      if (pbLaunch) {
        pbLaunch.addEventListener('click', () => {
          const gains = [120, 260, 380, 500]
          const labels = ['击中星环 +120', '触发 2× 倍率口 +260', '连撞弹柱 +380', '随机开彩大奖 +500!']
          const pick = Math.floor(Math.random() * gains.length)
          miniState.pinballScore += gains[pick]
          if (pbScore)
            pbScore.textContent = String(miniState.pinballScore)
          if (pbMsg)
            pbMsg.textContent = labels[pick]
          if (pbBall) {
            const rx = 40 + Math.floor(Math.random() * 140)
            const ry = -20 - Math.floor(Math.random() * 70)
            pbBall.style.transform = `translate(${rx}px, ${ry}px)`
          }
        })
      }
      return
    }

    if (appId === 'starplane') {
      miniAppBody.innerHTML
        = `<div class="plane-stage">`
          + `  <span style="font-size:11px;opacity:.82;">星际航程 · <strong id="planeDist">${miniState.planeDist}</strong> 光年</span>`
          + `  <span class="plane-sprite" id="planeSprite" aria-hidden="true">✈️</span>`
          + `  <span style="font-size:11px;opacity:.86;" id="planeTip">穿越星球引力，保持顺风滑翔</span>`
          + `</div>`
          + `<div class="mini-btn-row">`
          + `  <button type="button" class="mini-ctrl-btn is-primary" id="planeBoost">轻推跃迁虫洞 →</button>`
          + `</div>`

      const boost = document.getElementById('planeBoost')
      const sprite = document.getElementById('planeSprite')
      const distEl = document.getElementById('planeDist')
      const tipEl = document.getElementById('planeTip')
      if (boost) {
        boost.addEventListener('click', () => {
          miniState.planeDist += 45 + Math.floor(Math.random() * 90)
          if (distEl)
            distEl.textContent = String(miniState.planeDist)
          if (tipEl)
            tipEl.textContent = '已穿过虫洞，进入新星域！'
          if (sprite) {
            const tx = 20 + Math.floor(Math.random() * 110)
            const ty = -26 + Math.floor(Math.random() * 44)
            sprite.style.transform = `translate(${tx}px, ${ty}px) rotate(-12deg)`
          }
        })
      }
      return
    }

    if (appId === 'fc') {
      miniAppBody.innerHTML
        = `<div class="fc-screen" id="fcScreen">`
          + `<div>&gt; READY · FC CLOUD NES</div>`
          + `<div>&gt; SCORE: ${miniState.fcScore}</div>`
          + `<div>&gt; 按下 A / B 键即刻热身</div>`
          + `</div>`
          + `<div class="fc-pad">`
          + `  <span style="font-family:var(--font-mono);font-size:12px;">✚ D-PAD</span>`
          + `  <div style="display:flex;gap:8px;">`
          + `    <button type="button" class="mini-ctrl-btn" data-fc="B">B</button>`
          + `    <button type="button" class="mini-ctrl-btn is-primary" data-fc="A">A</button>`
          + `  </div>`
          + `</div>`

      miniAppBody.querySelectorAll('[data-fc]').forEach((btn) => {
        btn.addEventListener('click', () => {
          const key = btn.getAttribute('data-fc')
          miniState.fcScore += key === 'A' ? 100 : 50
          const screen = document.getElementById('fcScreen')
          if (screen) {
            screen.innerHTML
              = `<div>&gt; INPUT [${key}] · ${key === 'A' ? 'JUMP +100' : 'TURBO +50'}</div>`
                + `<div>&gt; SCORE: ${miniState.fcScore}</div>`
                + `<div>&gt; 在云居随时续关！</div>`
          }
        })
      })
      return
    }

    if (appId === 'couplet') {
      const item = COUPLETS[miniState.coupletIdx % COUPLETS.length]
      miniAppBody.innerHTML
        = `<div class="couplet-scroll">`
          + `  <span class="couplet-top">${item.top}</span>`
          + `  <p class="couplet-lines">${item.a}<br>${item.b}</p>`
          + `</div>`
          + `<div class="mini-btn-row">`
          + `  <button type="button" class="mini-ctrl-btn is-primary" id="nextCouplet">换一副春联</button>`
          + `</div>`

      const nextBtn = document.getElementById('nextCouplet')
      if (nextBtn) {
        nextBtn.addEventListener('click', () => {
          miniState.coupletIdx += 1
          renderMiniAppContent('couplet')
        })
      }
    }
  }

  let miniAppTrigger

  function openMiniApp(appId, trigger) {
    const app = APP_CATALOG[appId]
    if (!app || !miniAppSheet)
      return
    if (miniAppBadge) {
      miniAppBadge.className = `mini-app-badge ${app.iconClass}`
      miniAppBadge.innerHTML = app.iconHtml
    }
    if (miniAppTitle)
      miniAppTitle.textContent = app.name
    if (miniAppSubtitle)
      miniAppSubtitle.textContent = app.subtitle
    miniAppTrigger = trigger
    renderMiniAppContent(appId)
    miniAppSheet.hidden = false
    revealStage(null, miniAppSheet)
    miniAppClose.focus({ preventScroll: true })
  }

  function closeMiniApp() {
    if (miniAppSheet.hidden)
      return
    miniAppSheet.hidden = true
    miniAppTrigger?.focus({ preventScroll: true })
  }

  if (miniAppClose) {
    miniAppClose.addEventListener('click', closeMiniApp)
  }

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && miniAppSheet && !miniAppSheet.hidden) {
      closeMiniApp()
    }
  })

  // 绑定卡带芯片点击：未入盒则飞入云居，已入盒则轻点即开
  if (cartridgeRack) {
    cartridgeRack.addEventListener('click', (e) => {
      const chip = e.target.closest('.cartridge-chip')
      if (!chip || isFlying)
        return
      const appId = chip.getAttribute('data-app-id')
      if (!appId)
        return

      closeMiniApp()
      if (dockSlots.includes(appId)) {
        openMiniApp(appId, chip)
      }
      else {
        const iconEl = chip.querySelector('.chip-app-icon') || chip
        flyToDock(appId, iconEl)
      }
    })
  }

  // 轻点云居中已收起的应用
  if (collectionSlots) {
    collectionSlots.addEventListener('click', (e) => {
      const slot = e.target.closest('.dock-slot')
      if (!slot || isFlying)
        return
      const appId = slot.getAttribute('data-app-id')
      if (appId)
        openMiniApp(appId, slot)
    })
  }

  // 「演示收盒」按钮：自动挑一个未收纳的云应用演示飞入并秒开
  const autoDemoBtn = document.getElementById('autoDemoBtn')
  if (autoDemoBtn) {
    autoDemoBtn.addEventListener('click', () => {
      if (isFlying)
        return
      closeMiniApp()
      const candidates = ['ac', 'pinball', 'starplane', 'fc']
      const nextId = candidates.find((id) => {
        return !dockSlots.includes(id)
      }) || 'ac'

      const chip = cartridgeRack && cartridgeRack.querySelector(`[data-app-id="${nextId}"]`)
      const iconEl = chip ? chip.querySelector('.chip-app-icon') : null

      if (dockSlots.includes(nextId)) {
        openMiniApp(nextId, autoDemoBtn)
        return
      }

      flyToDock(nextId, iconEl, () => {
        setTimeout(() => {
          if (!isFlying && miniAppSheet.hidden)
            openMiniApp(nextId, autoDemoBtn)
        }, isReducedMotion() ? 0 : 400)
      })
    })
  }

  // 货架卡片的「在首屏试玩 ↑」联动
  document.querySelectorAll('[data-launch-demo]').forEach((btn) => {
    btn.addEventListener('click', () => {
      if (isFlying)
        return
      const appId = btn.getAttribute('data-launch-demo')
      if (!dockSlots.includes(appId)) {
        const idx = findTargetSlotIndex()
        dockSlots[idx] = appId
        renderDockUI(idx)
      }
      openMiniApp(appId, btn)
    })
  })

  renderDockUI(-1)
  cartridgeRack.closest('.dock-console').hidden = false

  /* ========================================================================
     5. 「一机四境」真机四截图切换（标签 + 底栏 + 卡片点击 + 滚动联动）
     ======================================================================== */
  const TOUR_META = [
    { label: '01 云居', desc: '你的随身云应用陈列架' },
    { label: '02 工坊', desc: '按用途与作者挑顺手工具与游戏' },
    { label: '03 寻乐', desc: '随手撞见有趣的新作品与彩蛋' },
    { label: '04 应用详情', desc: '看清开发者信息，一键打开或收进云居' },
  ]

  const tourPills = document.querySelectorAll('.tour-pill')
  const tourIndicator = document.getElementById('tourPillsIndicator')
  const tourSlides = document.querySelectorAll('.tour-slide')
  const tourCards = document.querySelectorAll('.tour-card')
  const pnavBtns = document.querySelectorAll('.pnav-btn')
  const tourStageNote = document.getElementById('tourStageNote')
  let currentTourStep = 0
  let lockScrollSyncUntil = 0

  function setTourStep(stepIndex, fromUserClick) {
    const idx = Math.max(0, Math.min(3, Number(stepIndex) || 0))
    if (fromUserClick) {
      lockScrollSyncUntil = Date.now() + 700
    }
    currentTourStep = idx

    tourPills.forEach((pill, i) => {
      const active = i === idx
      pill.classList.toggle('is-active', active)
      pill.setAttribute('aria-selected', String(active))
    })

    if (tourIndicator) {
      tourIndicator.style.transform = `translateX(calc(${idx * 100}% + ${idx * 4}px))`
    }

    tourSlides.forEach((slide) => {
      const sIdx = Number(slide.getAttribute('data-slide'))
      slide.classList.toggle('is-active', sIdx === idx)
    })

    tourCards.forEach((card) => {
      const cIdx = Number(card.getAttribute('data-step'))
      card.classList.toggle('is-active', cIdx === idx)
    })

    pnavBtns.forEach((btn) => {
      const bIdx = Number(btn.getAttribute('data-step'))
      btn.classList.toggle('is-active', bIdx === idx)
    })

    if (tourStageNote && TOUR_META[idx]) {
      tourStageNote.innerHTML
        = `当前画面：<strong>${TOUR_META[idx].label}</strong> — ${TOUR_META[idx].desc}`
    }
  }

  tourPills.forEach((pill) => {
    pill.addEventListener('click', () => {
      setTourStep(pill.getAttribute('data-step'), true)
    })
  })

  pnavBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      setTourStep(btn.getAttribute('data-step'), true)
    })
  })

  tourCards.forEach((card) => {
    card.addEventListener('click', () => {
      setTourStep(card.getAttribute('data-step'), true)
    })
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault()
        setTourStep(card.getAttribute('data-step'), true)
      }
    })
  })

  // 宽屏滚动时自动同步激活对应真机截图
  if ('IntersectionObserver' in window && tourCards.length) {
    const tourObserver = new IntersectionObserver(
      (entries) => {
        if (window.innerWidth <= 860)
          return
        if (Date.now() < lockScrollSyncUntil)
          return
        entries.forEach((entry) => {
          if (entry.isIntersecting && entry.intersectionRatio >= 0.55) {
            const step = Number(entry.target.getAttribute('data-step'))
            if (step !== currentTourStep) {
              setTourStep(step, false)
            }
          }
        })
      },
      { threshold: [0.55], rootMargin: '-18% 0px -28% 0px' },
    )
    tourCards.forEach((card) => {
      tourObserver.observe(card)
    })
  }

  setTourStep(0, false)

  /* ========================================================================
     6. 工坊与寻乐货架筛选 + 「随手寻一乐」随机抽取
     ======================================================================== */
  const filterChips = document.querySelectorAll('.filter-chip')
  const appCards = Array.prototype.slice.call(document.querySelectorAll('.app-card'))
  const serendipityBtn = document.getElementById('serendipityBtn')
  const serendipityBanner = document.getElementById('serendipityBanner')
  const serendipityText = document.getElementById('serendipityText')
  let lastPickedId = ''

  const SERENDIPITY_NOTES = {
    party: '「云乐坊间」—— 喊上朋友同屏或联机，三分钟就能开一局。',
    starplane: '「星纸」—— 折一架纸飞机，在星球与虫洞之间安静滑翔一会儿。',
    pinball: '「云乐弹珠」—— 拉一次发射杆，看弹珠撞开随机倍率口。',
    fc: '「FC 红白机」—— 收进云居，午休也能随时搓两局像素经典。',
    askta: '「问 TA」—— 从轻松破冰到认真深聊，陪你和重要的人好好对话。',
    couplet: '「AI 春联」—— 随时灵感来一副工整对联，过节不再词穷。',
    ac: '「云空调」—— 虽然毫无制冷效果，但打开瞬间心里已经凉了半截。',
    fan: '「云风扇」—— 纯 CSS 驱动的夏日老前辈，呼呼吹走焦躁。',
  }

  function applyFilter(cat) {
    filterChips.forEach((chip) => {
      const active = chip.getAttribute('data-filter') === cat
      chip.classList.toggle('is-active', active)
      chip.setAttribute('aria-pressed', String(active))
    })

    appCards.forEach((card) => {
      const cardCat = card.getAttribute('data-category')
      const visible = cat === 'all' || cardCat === cat
      card.classList.toggle('is-hidden', !visible)
    })
  }

  filterChips.forEach((chip) => {
    chip.addEventListener('click', () => {
      applyFilter(chip.getAttribute('data-filter'))
    })
  })

  if (serendipityBtn && appCards.length) {
    serendipityBtn.addEventListener('click', () => {
      applyFilter('all')
      serendipityBtn.classList.remove('is-rolling')
      void serendipityBtn.offsetWidth
      if (!isReducedMotion()) {
        serendipityBtn.classList.add('is-rolling')
      }

      const pool = appCards.filter((c) => {
        return c.getAttribute('data-card-id') !== lastPickedId
      })
      const chosen = pool[Math.floor(Math.random() * pool.length)] || appCards[0]
      const pickedId = chosen.getAttribute('data-card-id')
      lastPickedId = pickedId

      appCards.forEach((c) => {
        c.classList.remove('is-picked')
      })
      void chosen.offsetWidth
      chosen.classList.add('is-picked')

      if (serendipityBanner && serendipityText) {
        serendipityText.textContent = SERENDIPITY_NOTES[pickedId] || '为你随手发现一款好玩的云应用！'
        serendipityBanner.hidden = false
      }

      const rect = chosen.getBoundingClientRect()
      if (rect.top < 80 || rect.bottom > window.innerHeight - 20) {
        chosen.scrollIntoView({ behavior: isReducedMotion() ? 'auto' : 'smooth', block: 'center' })
      }
    })
  }

  /* ========================================================================
     7. 桌面精细指针的轻微 3D 倾斜与玻璃高光跟随（触屏与减动效自动跳过）
     ======================================================================== */
  const finePointer = window.matchMedia('(hover: hover) and (pointer: fine)')
  const tiltStage = document.querySelector('[data-tilt-stage]')

  if (tiltStage && finePointer.matches) {
    tiltStage.addEventListener('pointermove', (e) => {
      if (isReducedMotion())
        return
      const rect = tiltStage.getBoundingClientRect()
      const px = (e.clientX - rect.left) / rect.width
      const py = (e.clientY - rect.top) / rect.height
      const tiltY = (px - 0.5) * 9
      const tiltX = (0.5 - py) * 7

      tiltStage.style.setProperty('--tilt-x', `${tiltX.toFixed(2)}deg`)
      tiltStage.style.setProperty('--tilt-y', `${tiltY.toFixed(2)}deg`)
      tiltStage.style.setProperty('--sheen-x', `${(px * 100).toFixed(1)}%`)
      tiltStage.style.setProperty('--sheen-y', `${(py * 100).toFixed(1)}%`)
    })

    tiltStage.addEventListener('pointerleave', () => {
      tiltStage.style.setProperty('--tilt-x', '0deg')
      tiltStage.style.setProperty('--tilt-y', '0deg')
      tiltStage.style.setProperty('--sheen-x', '50%')
      tiltStage.style.setProperty('--sheen-y', '25%')
    })
  }
})()
