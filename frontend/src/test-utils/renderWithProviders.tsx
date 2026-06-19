import type { ReactElement, ReactNode } from 'react'
import { render, type RenderOptions } from '@testing-library/react'
import { TooltipProvider } from '@radix-ui/react-tooltip'

/**
 * Wraps `render` with the providers our components assume are present at the
 * app root. Use this in tests instead of `render` directly whenever the
 * component tree (or any descendant) renders a Radix Tooltip.
 */
export function renderWithProviders(
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>,
) {
  function Wrapper({ children }: { children: ReactNode }) {
    return <TooltipProvider delayDuration={0}>{children}</TooltipProvider>
  }
  return render(ui, { wrapper: Wrapper, ...options })
}
