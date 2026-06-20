import { useEffect, useState, type RefObject } from 'react'
import { invoke } from '@zero-apps/api/core'
import { isZeroNative } from '../mock-zero'
import { attachmentAssetUrlFromPath } from '../utils/vaultAttachments'

const IMAGE_MIME_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp']

function hasImageFiles(dt: DataTransfer): boolean {
  for (let i = 0; i < dt.items.length; i++) {
    const item = Reflect.get(dt.items, i) as DataTransferItem | undefined
    if (item?.kind === 'file' && IMAGE_MIME_TYPES.includes(item.type)) return true
  }
  return false
}

/** Upload an image file — saves to vault/attachments in the native bridge, returns data URL in browser. */
export async function uploadImageFile(file: File, vaultPath?: string): Promise<string> {
  if (isZeroNative() && vaultPath) {
    const buf = await file.arrayBuffer()
    const bytes = new Uint8Array(buf)
    let binary = ''
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes.at(i) ?? 0)
    const base64 = btoa(binary)
    const savedPath = await invoke<string>('save_image', {
      vaultPath,
      filename: file.name,
      data: base64,
    })
    return attachmentAssetUrlFromPath({ path: savedPath })
  }
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(reader.result as string)
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(file)
  })
}

// zero-native refactor: the legacy Tauri `tauri://drag-drop` event
// path was removed because zero-native does not emit those events and
// `getCurrentWindow().onDragDropEvent` is currently a stub. The HTML5
// DnD path below is the working path for both web and the zero-native
// WebView. When zero-native gains file-drop support, register the
// native listener via @zero-apps/api/window.

interface UseImageDropOptions {
  containerRef: RefObject<HTMLDivElement | null>
}

export function useImageDrop({ containerRef }: UseImageDropOptions) {
  const [isDragOver, setIsDragOver] = useState(false)

  // HTML5 DnD visual feedback; the browser/wkwebview fires these for both
  // in-window drags and (for the zero-native WebView) native file drops
  // once file-drop support is added. Until then, the editor handles
  // image uploads via its own paste/drop handlers.
  useEffect(() => {
    const container = containerRef.current
    if (!container) return

    const handleDragOver = (e: DragEvent) => {
      if (!e.dataTransfer || !hasImageFiles(e.dataTransfer)) return
      e.preventDefault()
      e.dataTransfer.dropEffect = 'copy'
      setIsDragOver(true)
    }

    const handleDragLeave = (e: DragEvent) => {
      if (!container.contains(e.relatedTarget as Node)) {
        setIsDragOver(false)
      }
    }

    const handleDrop = () => {
      setIsDragOver(false)
    }

    container.addEventListener('dragover', handleDragOver)
    container.addEventListener('dragleave', handleDragLeave)
    container.addEventListener('drop', handleDrop)

    return () => {
      container.removeEventListener('dragover', handleDragOver)
      container.removeEventListener('dragleave', handleDragLeave)
      container.removeEventListener('drop', handleDrop)
    }
  }, [containerRef])

  return { isDragOver }
}
