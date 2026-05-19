const BLOCKNOTE_MISSING_ID_ERROR = "Block doesn't have id"
const BLOCKNOTE_RECOVERY_BOUNDARY_NAME = 'BlockNoteRenderRecoveryBoundary'
const RECOVERED_BLOCKNOTE_RENDER_ERROR_MARK = '__tolariaRecoveredBlockNoteRenderError'
const RENDER_SPEC_ERROR_PATTERNS = [
  'Invalid array passed to renderSpec',
  'renderSpec',
  'Invalid tag',
]

type MarkedRecoveredBlockNoteRenderError = Error & {
  [RECOVERED_BLOCKNOTE_RENDER_ERROR_MARK]?: true
}

function hasRecoveredRenderErrorMark(error: unknown): boolean {
  if (!(error instanceof Error)) return false
  return Reflect.get(error as MarkedRecoveredBlockNoteRenderError, RECOVERED_BLOCKNOTE_RENDER_ERROR_MARK) === true
}

function matchesRenderSpecError(error: unknown): boolean {
  if (!(error instanceof Error)) return false
  return RENDER_SPEC_ERROR_PATTERNS.some(pattern =>
    error.message.includes(pattern)
  )
}

export function isRecoverableBlockNoteRenderError(error: unknown): boolean {
  if (!(error instanceof Error)) return false
  if (error.message.includes(BLOCKNOTE_MISSING_ID_ERROR)) return true
  if (matchesRenderSpecError(error)) return true
  return false
}

export function markRecoveredBlockNoteRenderError(error: unknown): void {
  if (!isRecoverableBlockNoteRenderError(error)) return
  const markedError = error as MarkedRecoveredBlockNoteRenderError
  Reflect.set(markedError, RECOVERED_BLOCKNOTE_RENDER_ERROR_MARK, true)
}

export function isRecoveredBlockNoteRenderError(
  error: unknown,
  componentStack: string,
): boolean {
  if (!isRecoverableBlockNoteRenderError(error)) return false
  if (hasRecoveredRenderErrorMark(error)) return true
  if (componentStack.includes(BLOCKNOTE_RECOVERY_BOUNDARY_NAME)) return true
  if (matchesRenderSpecError(error)) return true
  return false
}
