# react-pretext-editor

A React layout editor and renderer for rich text with free image placement, polygon text wrapping, multi-column layouts, and responsive breakpoints. Built on [@chenglou/pretext](https://github.com/chenglou/pretext) for precise text layout.

**Live demo**: <https://pretext-editor.asbjornenge.com>

![react-pretext-editor screenshot](https://ipfs.asbjornenge.com/QmdhbrAHgVwW15uyFwvisxJgGjqJv76kfpUfVbsf7VB7Yf)

## Features

- **Rich markdown editing** with bold, italic, links, lists, blockquotes, code blocks
- **Free image placement** with drag-and-drop positioning
- **Polygon text wrapping** around custom image shapes
- **Multi-column layouts** (1-3 columns) with balanced text flow
- **Responsive breakpoints** with per-breakpoint image positions, columns, and fonts
- **Initial/drop caps** with custom decorative fonts
- **Font selection** with configurable font options and sizes
- **Live preview** toggle within the editor
- **Keyboard shortcuts** for markdown (Cmd+B/I/K, wrap selection, smart lists)

## Installation

```bash
npm install react-pretext-editor
```

## Usage

### Editor

```tsx
import { Editor, parseMarkdown } from 'react-pretext-editor'
import type { LayoutData, FontOption } from 'react-pretext-editor'

const fonts: FontOption[] = [
  { name: 'Lato', bodyFont: '16px Lato, sans-serif' },
  { name: 'Georgia', bodyFont: '16px Georgia, serif' },
]

function App() {
  const [blocks, setBlocks] = useState(() => parseMarkdown('# Hello\n\nWorld'))
  const [layout, setLayout] = useState<LayoutData>({ images: [] })

  return (
    <Editor
      blocks={blocks}
      layout={layout}
      onLayoutChange={setLayout}
      onBlocksChange={setBlocks}
      availableFonts={fonts}
      width={1000}
      expandable
    />
  )
}
```

### Renderer (display only)

```tsx
import { Renderer } from 'react-pretext-editor'

function BlogPost({ blocks, layout }) {
  return (
    <Renderer
      blocks={blocks}
      layout={layout}
      availableFonts={fonts}
    />
  )
}
```

The Editor stores resolved font CSS (`bodyFontCSS`, `bodyLineHeight`, `headingLineHeight`, `initialCapFontCSS`) into `layoutData` whenever it changes — both on the top-level layout and on each breakpoint. This means a Renderer in another app can reproduce a saved layout exactly **without** needing the same `availableFonts` lookup; the `availableFonts` prop is only required if you want to override the stored values.

### Programmatic image insertion

```tsx
import { Editor } from 'react-pretext-editor'
import type { EditorRef } from 'react-pretext-editor'

const editorRef = useRef<EditorRef>(null)

editorRef.current?.addImage({
  filename: 'photo.jpg',
  alt: 'A photo',
  url: 'https://...',
  aspectRatio: 0.66,
  x: 50, y: 50, width: 200,
})

return <Editor ref={editorRef} {...props} />
```

The image is added to the currently-active breakpoint (or the default layout if no breakpoint is being edited).

## Editor Props

| Prop | Type | Description |
|------|------|-------------|
| `blocks` | `Block[]` | Content blocks (from `parseMarkdown`) |
| `layout` | `LayoutData` | Layout state (images, columns, fonts, breakpoints) |
| `onLayoutChange` | `(layout) => void` | Called when layout changes |
| `onBlocksChange` | `(blocks) => void` | Called when text content changes |
| `availableFonts` | `FontOption[]` | Font choices for the font selector |
| `availableInitialFonts` | `InitialCapOption[]` | Fonts for drop caps |
| `config` | `LayoutConfig` | Default layout config overrides |
| `resolveImageUrl` | `(url, filename) => string` | Custom image URL resolver |
| `width` | `number \| string` | Editor width |
| `height` | `number \| string` | Minimum editor height |
| `expandable` | `boolean` | Expand width when multiple panels are active |

`config` accepts a `defaultMode` of `'write'` or `'layout'` to control which mode the editor opens in.

## Data Model

### Block

```typescript
interface Block {
  type: 'heading' | 'paragraph' | 'list' | 'blockquote' | 'code' | 'hr'
  text: string
  segments?: TextSegment[]  // Inline formatting
  tag?: string              // h1/h2/h3, ul/ol
  items?: Block[]           // List items
  language?: string         // Code block language
}
```

### LayoutData

```typescript
interface LayoutData {
  images: LayoutImage[]
  columns?: number          // 1-3
  editorWidth?: number
  fontFamily?: string
  fontSize?: number
  initialCap?: boolean
  initialCapFont?: string
  initialCapSize?: number
  initialCapOffsetX?: number
  initialCapOffsetY?: number
  breakpoints?: LayoutBreakpoint[]
}
```

### LayoutImage

```typescript
interface LayoutImage {
  filename: string
  alt: string
  url: string
  aspectRatio: number
  x: number               // Absolute x position
  y: number               // Absolute y position
  width: number
  polygon?: PolygonPoint[] // Custom text wrapping shape
}
```

## Keyboard Shortcuts (Write mode)

| Shortcut | Action |
|----------|--------|
| `Cmd+B` | Bold |
| `Cmd+I` | Italic |
| `Cmd+K` | Insert link |
| `Tab` | Indent list item |
| `Shift+Tab` | Unindent list item |
| `Enter` in list | Continue list / break out if empty |
| Select + `*` | Wrap selection with `*...*` |
| Select + `` ` `` | Wrap selection with backticks |

## License

MIT
