import { EmulatedRegExp } from 'oniguruma-to-es'

const lang = Object.freeze({fileTypes:[],injectTo:["text.html.markdown"],injectionSelector:"L:text.html.markdown",name:"markdown-vue",patterns:[{include:"#vue-code-block"}],repository:{"vue-code-block":{begin:/*@__PURE__*/ new EmulatedRegExp("(^|^)(\\p{space}*)(`{3,}|~{3,})\\p{space}*(vue)((\\p{space}+|[\\,\\:\\?\\{])[^\\`\\~]*)?(?=\\n?$)","dgiv",{"strategy":"clip_search"}),beginCaptures:{"3":{name:"punctuation.definition.markdown"},"4":{name:"fenced_code.block.language.markdown"},"5":{name:"fenced_code.block.language.attributes.markdown",patterns:[]}},end:/*@__PURE__*/ new EmulatedRegExp("(^|^)((?!)|\\p{space}{0,3})((?!))\\p{space}*(?=\\n?$)","dgv",{"strategy":"clip_search"}),endCaptures:{"3":{name:"punctuation.definition.markdown"}},name:"markup.fenced_code.block.markdown",patterns:[{include:"text.html.vue"}]}},scopeName:"markdown.vue.codeblock",displayName:undefined,embeddedLangs:undefined,aliases:undefined})

export default [
lang
]
