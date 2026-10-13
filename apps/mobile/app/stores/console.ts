import type {
  DiagnosticLogEntry,
  DiagnosticLogLevel,
} from '~/utils/diagnostic-logs'
import { acceptHMRUpdate, defineStore } from 'pinia'
import {
  clearDiagnosticLogs,
  loadDiagnosticLogs,
  normalizeDiagnosticLogEntry,
  pruneDiagnosticLogs,
  saveDiagnosticLogs,
  serializeDiagnosticLogArgument,
} from '~/utils/diagnostic-logs'

export type LogLevel = DiagnosticLogLevel

// Console 格式化指令正则（%c, %s, %d, %i, %f, %o, %O, %%）
const FORMAT_SPECIFIER_REGEX = /%[csdifoO%]/
const FORMAT_PARSE_REGEX = /%%|%([csdifoO])/g

/** 单个文本片段，可带 CSS 样式 */
export interface LogSegment {
  text: string
  style?: string // CSS 样式字符串（来自 %c）
}

export interface LogEntry {
  id: number
  level: LogLevel
  timestamp: number
  /** 结构化的文本片段（支持 %c 样式渲染） */
  segments: LogSegment[]
  /** 纯文本内容（用于导出/搜索） */
  plain: string
}

const MAX_LOGS = 500

let _id = 0

// 安全的 CSS 属性白名单（防止 XSS）
const SAFE_CSS_PROPS = new Set([
  'color',
  'background',
  'background-color',
  'font-size',
  'font-weight',
  'font-style',
  'font-family',
  'text-decoration',
  'text-transform',
  'padding',
  'padding-left',
  'padding-right',
  'padding-top',
  'padding-bottom',
  'margin',
  'margin-left',
  'margin-right',
  'margin-top',
  'margin-bottom',
  'border',
  'border-radius',
  'border-color',
  'border-width',
  'border-style',
  'line-height',
  'letter-spacing',
  'display',
  'inline-size',
])

/** 过滤 CSS 样式，只保留安全属性 */
function sanitizeStyle(css: string): string {
  return css
    .split(';')
    .map(s => s.trim())
    .filter((s) => {
      const colonIdx = s.indexOf(':')
      if (colonIdx === -1)
        return false
      const prop = s.slice(0, colonIdx).trim().toLowerCase()
      return SAFE_CSS_PROPS.has(prop)
    })
    .join('; ')
}

/** 将任意值序列化为字符串 */
function stringifyArg(arg: unknown): string {
  return serializeDiagnosticLogArgument(arg)
}

/**
 * 解析 console 参数，处理格式化字符串中的 %c / %s / %d / %i / %f / %o / %O
 * 模拟 Chrome DevTools 的行为
 */
function parseArgs(args: unknown[]): { segments: LogSegment[], plain: string } {
  if (args.length === 0)
    return { segments: [], plain: '' }

  const first = args[0]

  // 第一个参数不是字符串，或不含格式化指令 → 简单拼接
  if (typeof first !== 'string' || !FORMAT_SPECIFIER_REGEX.test(first)) {
    const text = args.map(stringifyArg).join(' ')
    return { segments: [{ text }], plain: text }
  }

  const segments: LogSegment[] = []
  const plainParts: string[] = []
  let argIdx = 1
  let currentStyle: string | undefined

  // 按 %X 拆分格式化字符串
  let lastIndex = 0
  let match: RegExpExecArray | null

  // eslint-disable-next-line no-cond-assign
  while ((match = FORMAT_PARSE_REGEX.exec(first)) !== null) {
    // match 前面的文本
    const before = first.slice(lastIndex, match.index)
    if (before) {
      segments.push({ text: before, style: currentStyle })
      plainParts.push(before)
    }
    lastIndex = FORMAT_PARSE_REGEX.lastIndex

    if (match[0] === '%%') {
      // 转义的 %
      segments.push({ text: '%', style: currentStyle })
      plainParts.push('%')
      continue
    }

    const specifier = match[1]
    const arg = argIdx < args.length ? args[argIdx++] : undefined

    switch (specifier) {
      case 'c':
        // %c → 切换样式，arg 是 CSS 字符串
        currentStyle = typeof arg === 'string' ? sanitizeStyle(arg) : undefined
        break
      case 's':
        {
          const text = stringifyArg(arg)
          segments.push({ text, style: currentStyle })
          plainParts.push(text)
        }
        break
      case 'd':
      case 'i':
        {
          const text = String(Number.parseInt(String(arg)) || 0)
          segments.push({ text, style: currentStyle })
          plainParts.push(text)
        }
        break
      case 'f':
        {
          const text = String(Number.parseFloat(String(arg)) || 0)
          segments.push({ text, style: currentStyle })
          plainParts.push(text)
        }
        break
      case 'o':
      case 'O':
        {
          const text = stringifyArg(arg)
          segments.push({ text, style: currentStyle })
          plainParts.push(text)
        }
        break
    }
  }

  // 剩余文本
  const tail = first.slice(lastIndex)
  if (tail) {
    segments.push({ text: tail, style: currentStyle })
    plainParts.push(tail)
  }

  // 多余的参数追加到末尾
  if (argIdx < args.length) {
    const extra = args.slice(argIdx).map(stringifyArg).join(' ')
    segments.push({ text: ` ${extra}` })
    plainParts.push(` ${extra}`)
  }

  return { segments, plain: plainParts.join('') }
}

/**
 * 应用内控制台日志 Store
 * 拦截 console 方法，在移动端无 DevTools 时提供便捷的日志查看能力
 */
export const useConsoleStore = defineStore('console', () => {
  const logs = ref<LogEntry[]>([])
  const diagnosticLogs = ref<DiagnosticLogEntry[]>(
    import.meta.client ? loadDiagnosticLogs(localStorage) : [],
  )
  const capturing = ref(false)
  let persistTimer: ReturnType<typeof setTimeout> | undefined

  // 保存原始 console 方法
  const _originals: Record<LogLevel, (...args: unknown[]) => void> = {
    log: console.log.bind(console), // eslint-disable-line no-console
    info: console.info.bind(console), // eslint-disable-line no-console
    warn: console.warn.bind(console),
    error: console.error.bind(console),
    debug: console.debug.bind(console), // eslint-disable-line no-console
  }

  function addLog(level: LogLevel, args: unknown[]) {
    const { segments, plain } = parseArgs(args)
    const timestamp = Date.now()
    logs.value.push({
      id: ++_id,
      level,
      timestamp,
      segments,
      plain,
    })
    // 超出上限时移除最早的
    if (logs.value.length > MAX_LOGS) {
      logs.value = logs.value.slice(-MAX_LOGS)
    }

    const diagnosticEntry = normalizeDiagnosticLogEntry({
      level,
      message: plain,
      timestamp,
    })
    if (diagnosticEntry) {
      diagnosticLogs.value = pruneDiagnosticLogs([
        ...diagnosticLogs.value,
        diagnosticEntry,
      ], timestamp)
      scheduleDiagnosticPersistence()
    }
  }

  function scheduleDiagnosticPersistence() {
    if (!import.meta.client)
      return
    const storage = globalThis.localStorage
    if (!storage)
      return
    if (persistTimer)
      clearTimeout(persistTimer)
    persistTimer = setTimeout(() => {
      diagnosticLogs.value = saveDiagnosticLogs(storage, diagnosticLogs.value)
      persistTimer = undefined
    }, 150)
  }

  function startCapture() {
    if (capturing.value)
      return
    capturing.value = true

    const levels: LogLevel[] = ['log', 'info', 'warn', 'error', 'debug']
    const mutableConsole = console as unknown as Record<LogLevel, (...args: unknown[]) => void>
    for (const level of levels) {
      mutableConsole[level] = (...args: unknown[]) => {
        _originals[level](...args) // 仍输出到真实 console
        addLog(level, args)
      }
    }
  }

  function stopCapture() {
    if (!capturing.value)
      return
    capturing.value = false

    const levels: LogLevel[] = ['log', 'info', 'warn', 'error', 'debug']
    const mutableConsole = console as unknown as Record<LogLevel, (...args: unknown[]) => void>
    for (const level of levels) {
      mutableConsole[level] = _originals[level]
    }
  }

  function clearLogs() {
    logs.value = []
    diagnosticLogs.value = []
    _id = 0
    if (persistTimer) {
      clearTimeout(persistTimer)
      persistTimer = undefined
    }
    if (import.meta.client)
      clearDiagnosticLogs(localStorage)
  }

  return {
    logs,
    diagnosticLogs,
    capturing,
    startCapture,
    stopCapture,
    clearLogs,
  }
})

if (import.meta.hot)
  import.meta.hot.accept(acceptHMRUpdate(useConsoleStore, import.meta.hot))
