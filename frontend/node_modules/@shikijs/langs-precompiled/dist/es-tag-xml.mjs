import xml from './xml.mjs'

const lang = Object.freeze({fileTypes:["js","jsx","ts","tsx","html","vue","svelte","php","res"],injectTo:["source.ts","source.js"],injectionSelector:"L:source.js -comment -string, L:source.js -comment -string, L:source.jsx -comment -string,  L:source.js.jsx -comment -string, L:source.ts -comment -string, L:source.tsx -comment -string, L:source.rescript -comment -string",injections:{"L:source":{patterns:[{match:/</dgv,name:"invalid.illegal.bad-angle-bracket.html"}]}},name:"es-tag-xml",patterns:[{begin:/(\p{space}?\/\*\p{space}?(xml|svg|inline-svg|inline-xml)\p{space}?\*\/\p{space}?)(`)/dgiv,beginCaptures:{"1":{name:"comment.block"}},end:/(`)/dgv,patterns:[{include:"text.xml"}]},{begin:/(\p{space}*((?:|inline-)xml))(`)/dgiv,beginCaptures:{"1":{name:"comment.block"}},end:/(`)/dgv,patterns:[{include:"text.xml"}]},{begin:/(?<=[\(\,\:\=\p{space}]|\$\()\p{space}*(((\/\*)|(\/\/))\p{space}?(xml|svg|inline-svg|inline-xml) {0,1000}\*?\/?) {0,1000}(?=\n?$)/dgiv,beginCaptures:{"1":{name:"comment.line"}},end:/(`)[^\n]*/dgv,patterns:[{begin:/()/dgvy,end:/(`)/dgv},{include:"text.xml"}]}],scopeName:"inline.es6-xml",displayName:undefined,embeddedLangs:["xml"],aliases:undefined})

export default [
...xml,
lang
]
