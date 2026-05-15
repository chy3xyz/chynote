import typescript from './typescript.mjs'
import css from './css.mjs'
import javascript from './javascript.mjs'

const lang = Object.freeze({fileTypes:["js","jsx","ts","tsx","html","vue","svelte","php","res"],injectTo:["source.ts","source.js"],injectionSelector:"L:source.js -comment -string, L:source.js -comment -string, L:source.jsx -comment -string,  L:source.js.jsx -comment -string, L:source.ts -comment -string, L:source.tsx -comment -string, L:source.rescript -comment -string, L:source.vue -comment -string, L:source.svelte -comment -string, L:source.php -comment -string, L:source.rescript -comment -string",injections:{"L:source":{patterns:[{match:/</dgv,name:"invalid.illegal.bad-angle-bracket.html"}]}},name:"es-tag-css",patterns:[{begin:/(\p{space}?\/\*\p{space}?((?:|inline-)css)\p{space}?\*\/\p{space}?)(`)/dgiv,beginCaptures:{"1":{name:"comment.block"}},end:/(`)/dgv,patterns:[{include:"source.ts#template-substitution-element"},{include:"source.css"},{include:"inline.es6-htmlx#template"}]},{begin:/(\p{space}*((?:|inline-)css))(`)/dgiv,beginCaptures:{"1":{name:"comment.block"}},end:/(`)/dgv,patterns:[{include:"source.ts#template-substitution-element"},{include:"source.css"},{include:"inline.es6-htmlx#template"},{include:"string.quoted.other.template.js"}]},{begin:/(?<=[\(\,\:\=\p{space}]|\$\()\p{space}*(((\/\*)|(\/\/))\p{space}?((?:|inline-)css) {0,1000}\*?\/?) {0,1000}(?=\n?$)/dgiv,beginCaptures:{"1":{name:"comment.line"}},end:/(`)[^\n]*/dgv,patterns:[{begin:/()/dgvy,end:/(`)/dgv},{include:"source.ts#template-substitution-element"},{include:"source.css"}]},{begin:/(\$\{)/dgv,beginCaptures:{"1":{name:"entity.name.tag"}},end:/(\})/dgv,endCaptures:{"1":{name:"entity.name.tag"}},patterns:[{include:"source.ts#template-substitution-element"},{include:"source.js"}]}],scopeName:"inline.es6-css",displayName:undefined,embeddedLangs:["typescript","css","javascript"],aliases:undefined})

export default [
...typescript,
...css,
...javascript,
lang
]
