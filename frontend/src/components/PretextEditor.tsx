import { useState, useCallback } from 'react'
import { Editor, Renderer, parseMarkdown } from 'react-pretext-editor'
import type { Block, LayoutData } from 'react-pretext-editor'

const defaultFonts = [
  { name: 'Lato', bodyFont: '16px Lato, sans-serif' },
  { name: 'Georgia', bodyFont: '16px Georgia, serif' },
  { name: 'Inter', bodyFont: '16px Inter, sans-serif' },
]

export function PretextEditor({
  content,
  onChange,
  readOnly = false,
}: {
  content: string
  onChange?: (content: string) => void
  readOnly?: boolean
}) {
  const [blocks, setBlocks] = useState<Block[]>(() => parseMarkdown(content))
  const [layout, setLayout] = useState<LayoutData>({ images: [] })

  const handleBlocksChange = useCallback((newBlocks: Block[]) => {
    setBlocks(newBlocks)
    if (onChange) {
      const markdown = blocksToMarkdown(newBlocks)
      onChange(markdown)
    }
  }, [onChange])

  if (readOnly) {
    return (
      <Renderer
        blocks={blocks}
        layout={layout}
        availableFonts={defaultFonts}
      />
    )
  }

  return (
    <Editor
      blocks={blocks}
      layout={layout}
      onLayoutChange={setLayout}
      onBlocksChange={handleBlocksChange}
      availableFonts={defaultFonts}
      width="100%"
      height={600}
      expandable
    />
  )
}

function blocksToMarkdown(blocks: Block[]): string {
  return blocks.map(block => {
    switch (block.type) {
      case 'heading':
        const prefix = '#'.repeat(parseInt(block.tag?.replace('h', '') || '1'))
        return `${prefix} ${block.text}\n`
      case 'paragraph':
        return `${block.text}\n`
      case 'list':
        return (block.items || []).map(item => `- ${item.text}`).join('\n') + '\n'
      case 'blockquote':
        return `> ${block.text}\n`
      case 'code':
        return `\`\`\`${block.language || ''}\n${block.text}\n\`\`\`\n`
      case 'hr':
        return '---\n'
      default:
        return `${block.text}\n`
    }
  }).join('\n')
}
