<script setup lang="ts">
import type { MarkdownIt } from 'markstream-vue'
import MarkdownRender from 'markstream-vue'

const props = defineProps<{
  content: string
  final: boolean
}>()

function isSafeMarkdownLink(url: string) {
  const normalized = url
    .trim()
    .split('')
    .filter((char) => {
      const code = char.charCodeAt(0)
      return code > 0x20 && code !== 0x7F && !(code >= 0x80 && code <= 0x9F)
    })
    .join('')
    .toLowerCase()

  if (!normalized)
    return false

  return normalized.startsWith('#')
    || normalized.startsWith('/')
    || normalized.startsWith('./')
    || normalized.startsWith('../')
    || normalized.startsWith('http://')
    || normalized.startsWith('https://')
    || normalized.startsWith('mailto:')
    || normalized.startsWith('tel:')
}

function configureAgentMarkdown(md: MarkdownIt) {
  md.disable('image')
  md.set({ validateLink: isSafeMarkdownLink })
  return md
}
</script>

<template>
  <MarkdownRender
    class="agent-markdown-preview"
    :content="props.content"
    :custom-markdown-it="configureAgentMarkdown"
    :fade="false"
    :final="props.final"
    html-policy="escape"
    mode="chat"
    :max-live-nodes="0"
    :batch-rendering="true"
    :render-batch-size="16"
    :render-batch-delay="8"
    :render-batch-budget-ms="4"
    smooth-streaming="auto"
    :typewriter="true"
  />
</template>

<style scoped>
.agent-markdown-preview {
  overflow-wrap: anywhere;
  white-space: normal;
  font-size: 14px;
  line-height: 1.55;
}

.agent-markdown-preview :deep(*) {
  overflow-wrap: anywhere;
}

.agent-markdown-preview :deep(p),
.agent-markdown-preview :deep(ul),
.agent-markdown-preview :deep(ol),
.agent-markdown-preview :deep(pre),
.agent-markdown-preview :deep(blockquote),
.agent-markdown-preview :deep(table) {
  margin: 0 0 0.72em;
}

.agent-markdown-preview :deep(:first-child) {
  margin-top: 0;
}

.agent-markdown-preview :deep(:last-child) {
  margin-bottom: 0;
}

.agent-markdown-preview :deep(h1),
.agent-markdown-preview :deep(h2),
.agent-markdown-preview :deep(h3),
.agent-markdown-preview :deep(h4) {
  margin: 0.88em 0 0.45em;
  font-size: 1em;
  font-weight: 800;
  line-height: 1.35;
}

.agent-markdown-preview :deep(ul),
.agent-markdown-preview :deep(ol) {
  padding-left: 1.35em;
}

.agent-markdown-preview :deep(li + li) {
  margin-top: 0.18em;
}

.agent-markdown-preview :deep(a) {
  color: var(--ion-color-primary);
  font-weight: 700;
  text-decoration: none;
}

.agent-markdown-preview :deep(a:active) {
  opacity: 0.7;
}

.agent-markdown-preview :deep(code) {
  border-radius: 6px;
  padding: 0.12em 0.35em;
  color: var(--agent-accent-text, var(--ion-color-primary));
  background: var(--agent-panel-soft, rgba(0, 0, 0, 0.06));
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 0.92em;
}

.agent-markdown-preview :deep(pre) {
  overflow-x: auto;
  border-radius: 12px;
  padding: 10px 11px;
  background: var(--agent-panel-soft, rgba(0, 0, 0, 0.06));
}

.agent-markdown-preview :deep(pre code) {
  display: block;
  padding: 0;
  color: inherit;
  background: transparent;
  white-space: pre;
}

.agent-markdown-preview :deep(blockquote) {
  border-left: 3px solid var(--agent-border, rgba(0, 122, 255, 0.2));
  padding-left: 10px;
  color: var(--agent-muted, var(--ion-color-medium));
}

.agent-markdown-preview :deep(table) {
  display: block;
  max-width: 100%;
  overflow-x: auto;
  border-collapse: collapse;
}

.agent-markdown-preview :deep(th),
.agent-markdown-preview :deep(td) {
  border: 1px solid var(--agent-border, rgba(0, 122, 255, 0.14));
  padding: 5px 7px;
  text-align: left;
  vertical-align: top;
}
</style>
