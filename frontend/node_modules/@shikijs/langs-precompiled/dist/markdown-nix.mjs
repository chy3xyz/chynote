import { EmulatedRegExp } from 'oniguruma-to-es'

const lang = Object.freeze({fileTypes:[],injectTo:["text.html.markdown"],injectionSelector:"L:text.html.markdown",name:"markdown-nix",patterns:[{include:"#nix-code-block"}],repository:{"nix-code-block":{begin:/*@__PURE__*/ new EmulatedRegExp("(^|^)(\\p{space}*)(`{3,}|~{3,})\\p{space}*(nix)(\\p{space}+[^\\`\\~]*)?(?=\\n?$)","dgiv",{"strategy":"clip_search"}),beginCaptures:{"3":{name:"punctuation.definition.markdown"},"5":{name:"fenced_code.block.language"},"6":{name:"fenced_code.block.language.attributes"}},end:/*@__PURE__*/ new EmulatedRegExp("(^|^)((?!)|\\p{space}{0,3})((?!))\\p{space}*(?=\\n?$)","dgv",{"strategy":"clip_search"}),endCaptures:{"3":{name:"punctuation.definition.markdown"}},name:"markup.fenced_code.block.markdown",patterns:[{begin:/*@__PURE__*/ new EmulatedRegExp("(^|^)(\\p{space}*)([^\\n]*)","dgv",{"strategy":"clip_search"}),contentName:"meta.embedded.block.nix",patterns:[{include:"source.nix"}],while:/*@__PURE__*/ new EmulatedRegExp("(^|^)(?!\\p{space}*([\\`\\~]{3,})\\p{space}*(?=\\n?$))","dgv",{"strategy":"clip_search"})}]}},scopeName:"markdown.nix.codeblock",displayName:undefined,embeddedLangs:undefined,aliases:undefined})

export default [
lang
]
