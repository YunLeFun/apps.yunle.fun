import type { WebBuildPage } from './web-build-page'

const palettes = {
  indigo: ['#f5f3ff', '#171334', '#5141ab'],
  moss: ['#ebf2e8', '#122c22', '#24593d'],
  clay: ['#fff1e9', '#352018', '#963f25'],
  ocean: ['#ecf6fa', '#122b3b', '#185a7a'],
} as const

export function renderWebBuildPage(page: WebBuildPage, reportLink?: string): string {
  const [background, ink, accent] = palettes[page.palette]
  const title = escapeText(page.title)
  const sections = page.sections.map((section) => {
    const heading = escapeText(section.title)
    const content = `<p>${escapeText(section.text)}</p>`
    return section.expandable
      ? `<details><summary>${heading}</summary>${content}</details>`
      : `<section><h2>${heading}</h2>${content}</section>`
  }).join('')
  const report = reportLink ? `<a href="${escapeText(reportLink)}">举报网页</a>` : ''

  return `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow"><title>${title} · 云乐坊</title>
<style>
*{box-sizing:border-box}body{margin:0;background:${background};color:${ink};font:1rem/1.65 system-ui,sans-serif;overflow-wrap:anywhere}
main,footer{width:min(100% - 2rem,42rem);margin:auto}
header{padding:clamp(2rem,8vw,5rem) 0 1.8rem}
h1,h2,p{margin:0}h1{font-size:clamp(2rem,7vw,4rem);letter-spacing:-.035em;line-height:1.12}
header p{margin-top:1rem;font-size:1.08rem}p{white-space:pre-wrap}
section,details{background:#fff9;padding:1.25rem 1.4rem;margin-bottom:1rem;border:1px solid #0001;border-radius:1.1rem}
h2,summary{font-size:1.15rem;font-weight:700;line-height:1.4;color:${accent}}summary{cursor:pointer}
section p,details p{margin-top:.65rem}footer{display:flex;flex-wrap:wrap;gap:.5rem 1.25rem;justify-content:space-between;padding:1.25rem .2rem 2rem;font-size:.88rem}a{color:${accent}}
</style></head><body>
<main><header><h1>${title}</h1><p>${escapeText(page.description)}</p></header>${sections}</main>
<footer><span>用户使用云乐坊 AI 制作</span>${report}</footer>
</body></html>`
}

function escapeText(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll('\'', '&#39;')
}
