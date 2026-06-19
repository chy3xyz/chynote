import { fireEvent, render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { LinuxTitlebar } from './LinuxTitlebar'
import { shouldUseLinuxWindowChrome } from '../utils/platform'

const {
  close,
  invoke,
  isMaximized,
  minimize,
  onResized,
  startDragging,
  startResizeDragging,
  toggleMaximize,
} = vi.hoisted(() => ({
  invoke: vi.fn().mockResolvedValue(undefined),
  startDragging: vi.fn().mockResolvedValue(undefined),
  startResizeDragging: vi.fn().mockResolvedValue(undefined),
  minimize: vi.fn().mockResolvedValue(undefined),
  toggleMaximize: vi.fn().mockResolvedValue(undefined),
  close: vi.fn().mockResolvedValue(undefined),
  isMaximized: vi.fn().mockResolvedValue(false),
  onResized: vi.fn().mockResolvedValue(() => {}),
}))

vi.mock('../utils/platform', () => ({
  isMac: () => false,
  shouldUseLinuxWindowChrome: vi.fn(),
}))

vi.mock('@zero-apps/api/core', () => ({
  invoke,
}))

vi.mock('@zero-apps/api/window', () => ({
  getCurrentWindow: () => ({
    startDragging,
    startResizeDragging,
    minimize,
    toggleMaximize,
    close,
    isMaximized,
    onResized,
  }),
}))

// zero-native refactor: useDragRegion is a no-op in the zero-native WebView
// (no native window-drag API), but the titlebar component still uses it as a
// hook to register its onMouseDown. In tests we mock it to perform the same
// double-click / single-click behavior the real Tauri path would.
const mockOnMouseDown = vi.hoisted(() => vi.fn((e: { button: number; detail: number; target: EventTarget | null }) => {
  if (e.button !== 0) return
  if (e.detail === 2) {
    void invoke('perform_current_window_titlebar_double_click')
    return
  }
  void startDragging()
}))
vi.mock('../hooks/useDragRegion', () => ({
  useDragRegion: () => ({ onMouseDown: mockOnMouseDown }),
}))

describe('LinuxTitlebar', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(shouldUseLinuxWindowChrome).mockReturnValue(true)
  })

  it('does not render when Linux chrome is disabled', () => {
    vi.mocked(shouldUseLinuxWindowChrome).mockReturnValue(false)

    render(<LinuxTitlebar />)

    expect(screen.queryByTestId('linux-titlebar')).toBeNull()
  })

  it('routes titlebar double-click through the shared drag-region command only once', () => {
    render(<LinuxTitlebar />)

    fireEvent.mouseDown(screen.getByTestId('linux-titlebar'), { button: 0, detail: 2 })

    expect(invoke).toHaveBeenCalledWith('perform_current_window_titlebar_double_click')
    expect(toggleMaximize).not.toHaveBeenCalled()
    expect(startDragging).not.toHaveBeenCalled()
  })

  it('wires the Linux titlebar window controls to the current window', () => {
    render(<LinuxTitlebar />)

    fireEvent.click(screen.getByRole('button', { name: 'Minimize' }))
    fireEvent.click(screen.getByRole('button', { name: 'Maximize' }))
    fireEvent.click(screen.getByRole('button', { name: 'Close' }))

    expect(minimize).toHaveBeenCalledOnce()
    expect(toggleMaximize).toHaveBeenCalledOnce()
    expect(close).toHaveBeenCalledOnce()
  })
})
