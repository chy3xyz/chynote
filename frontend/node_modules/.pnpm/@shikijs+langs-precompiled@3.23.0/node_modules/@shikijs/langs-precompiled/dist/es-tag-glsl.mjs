import typescript from './typescript.mjs'
import glsl from './glsl.mjs'
import javascript from './javascript.mjs'

const lang = Object.freeze({fileTypes:["js","jsx","ts","tsx","html","vue","svelte","php","res"],injectTo:["source.ts","source.js"],injectionSelector:"L:source.js -comment -string, L:source.js -comment -string, L:source.jsx -comment -string,  L:source.js.jsx -comment -string, L:source.ts -comment -string, L:source.tsx -comment -string, L:source.rescript -comment -string",injections:{"L:source":{patterns:[{match:/</dgv,name:"invalid.illegal.bad-angle-bracket.html"}]}},name:"es-tag-glsl",patterns:[{begin:/(\p{space}?\/\*\p{space}?((?:|inline-)glsl)\p{space}?\*\/\p{space}?)(`)/dgiv,beginCaptures:{"1":{name:"comment.block"}},end:/(`)/dgv,patterns:[{include:"source.ts#template-substitution-element"},{include:"source.glsl"},{include:"inline.es6-htmlx#template"}]},{begin:/(\p{space}*((?:|inline-)glsl))(`)/dgiv,beginCaptures:{"1":{name:"comment.block"}},end:/(`)/dgv,patterns:[{include:"source.ts#template-substitution-element"},{include:"source.glsl"},{include:"inline.es6-htmlx#template"},{include:"string.quoted.other.template.js"}]},{begin:/(?<=[\(\,\:\=\p{space}]|\$\()\p{space}*(((\/\*)|(\/\/))\p{space}?((?:|inline-)glsl) {0,1000}\*?\/?) {0,1000}(?=\n?$)/dgiv,beginCaptures:{"1":{name:"comment.line"}},end:/(`)[^\n]*/dgv,patterns:[{begin:/()/dgvy,end:/(`)/dgv},{include:"source.ts#template-substitution-element"},{include:"source.glsl"}]},{begin:/(\$\{)/dgv,beginCaptures:{"1":{name:"entity.name.tag"}},end:/(\})/dgv,endCaptures:{"1":{name:"entity.name.tag"}},patterns:[{include:"source.ts#template-substitution-element"},{include:"source.js"}]}],scopeName:"inline.es6-glsl",displayName:undefined,embeddedLangs:["typescript","glsl","javascript"],aliases:undefined})

export default [
...typescript,
...glsl,
...javascript,
lang
]
