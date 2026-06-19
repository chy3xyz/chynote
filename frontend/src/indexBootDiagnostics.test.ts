import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

function inlineScriptAt(index: number): string {
  const indexHtml = readFileSync(`${process.cwd()}/index.html`, 'utf8')
  // index.html has multiple <script> blocks: the first is an Array polyfill,
  // the second is the boot/error handler. Tests target the boot handler.
  const matches = [...indexHtml.matchAll(/<script>\s*([\s\S]*?)\s*<\/script>/g)]
  if (!matches[index]) throw new Error(`index.html script at index ${index} was not found`)
  return matches[index][1]
}

describe('index startup script', () => {
  it('does not ship a visible boot diagnostics element by default', () => {
    const indexHtml = readFileSync(`${process.cwd()}/index.html`, 'utf8')

    expect(indexHtml).not.toContain('Chynote boot: HTML parsed')
    expect(indexHtml).not.toContain('<pre id="chynote-boot-diagnostics"')
  })

  it('does not show the boot overlay for ResizeObserver loop notifications', () => {
    document.body.innerHTML = ''
    new Function(inlineScriptAt(1))()

    const event = new ErrorEvent('error', {
      cancelable: true,
      message: 'ResizeObserver loop completed with undelivered notifications.',
    })
    window.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(document.body.children).toHaveLength(0)
  })

  it('does not create a visible boot overlay for real startup errors', () => {
    document.body.innerHTML = ''
    new Function(inlineScriptAt(1))()

    window.dispatchEvent(new ErrorEvent('error', {
      message: 'startup failed',
      filename: 'app.js',
      lineno: 1,
      colno: 2,
    }))

    expect(document.body.children).toHaveLength(0)
  })
})
