declare module 'react-pretext-editor' {
  import type { ReactNode } from 'react'

  export interface Block {
    type: string
    tag?: string
    text?: string
    items?: Array<{ text: string }>
    language?: string
  }

  export interface LayoutData {
    images: Array<{ src: string; alt?: string }>
  }

  export interface EditorProps {
    blocks: Block[]
    layout: LayoutData
    onLayoutChange?: (layout: LayoutData) => void
    onBlocksChange?: (blocks: Block[]) => void
    availableFonts?: Array<{ name: string; bodyFont: string }>
    width?: string
    height?: number
    expandable?: boolean
  }

  export interface RendererProps {
    blocks: Block[]
    layout: LayoutData
    availableFonts?: Array<{ name: string; bodyFont: string }>
  }

  export function Editor(props: EditorProps): JSX.Element
  export function Renderer(props: RendererProps): JSX.Element
  export function parseMarkdown(content: string): Block[]
}