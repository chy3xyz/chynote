import html from './html.mjs'

const lang = Object.freeze({displayName:"HTML (Derivative)",injections:{"R:text.html - (comment.block, text.html meta.embedded, meta.tag.*.*.html, meta.tag.*.*.*.html, meta.tag.*.*.*.*.html)":{patterns:[{match:/</dgv,name:"invalid.illegal.bad-angle-bracket.html"}]}},name:"html-derivative",patterns:[{include:"text.html.basic#core-minus-invalid"},{begin:/(<\/?)([\p{L}\p{M}\p{N}\p{Pc}][^\<\>\p{space}]*)(?<!\/)/dgv,beginCaptures:{"1":{name:"punctuation.definition.tag.begin.html"},"2":{name:"entity.name.tag.html"}},end:/((?: ?\/)?>)/dgv,endCaptures:{"1":{name:"punctuation.definition.tag.end.html"}},name:"meta.tag.other.unrecognized.html.derivative",patterns:[{include:"text.html.basic#attribute"}]}],scopeName:"text.html.derivative",embeddedLangs:["html"],aliases:undefined})

export default [
...html,
lang
]
