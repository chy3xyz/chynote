import javascript from './javascript.mjs'

const lang = Object.freeze({fileTypes:[],injectTo:["source.vue"],injectionSelector:"L:source.css -comment, L:source.postcss -comment, L:source.sass -comment, L:source.stylus -comment",name:"vue-sfc-style-variable-injection",patterns:[{include:"#vue-sfc-style-variable-injection"}],repository:{"vue-sfc-style-variable-injection":{begin:/\b(v-bind)\p{space}*\(/dgv,beginCaptures:{"1":{name:"entity.name.function"}},end:/\)/dgv,name:"vue.sfc.style.variable.injection.v-bind",patterns:[{begin:/(["'])/dgv,beginCaptures:{"1":{name:"punctuation.definition.tag.begin.html"}},end:/((?!))/dgv,endCaptures:{"1":{name:"punctuation.definition.tag.end.html"}},name:"source.ts.embedded.html.vue",patterns:[{include:"source.js"}]},{include:"source.js"}]}},scopeName:"vue.sfc.style.variable.injection",displayName:undefined,embeddedLangs:["javascript"],aliases:undefined})

export default [
...javascript,
lang
]
