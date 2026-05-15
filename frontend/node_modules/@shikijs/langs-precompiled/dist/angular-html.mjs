import html from './html.mjs'
import angular_expression from './angular-expression.mjs'
import angular_let_declaration from './angular-let-declaration.mjs'
import angular_template from './angular-template.mjs'
import angular_template_blocks from './angular-template-blocks.mjs'

const lang = Object.freeze({displayName:"Angular HTML",injections:{"R:text.html - (comment.block, text.html meta.embedded, meta.tag.*.*.html, meta.tag.*.*.*.html, meta.tag.*.*.*.*.html)":{patterns:[{match:/</dgv,name:"invalid.illegal.bad-angle-bracket.html"}]}},name:"angular-html",patterns:[{include:"text.html.basic#core-minus-invalid"},{begin:/(<\/?)([\p{L}\p{M}\p{N}\p{Pc}][^\>\p{space}]*)(?<!\/)/dgv,beginCaptures:{"1":{name:"punctuation.definition.tag.begin.html"},"2":{name:"entity.name.tag.html"}},end:/((?: ?\/)?>)/dgv,endCaptures:{"1":{name:"punctuation.definition.tag.end.html"}},name:"meta.tag.other.unrecognized.html.derivative",patterns:[{include:"text.html.basic#attribute"}]}],scopeName:"text.html.derivative.ng",embeddedLangs:["html","angular-expression","angular-let-declaration","angular-template","angular-template-blocks"],aliases:undefined})

export default [
...html,
...angular_expression,
...angular_let_declaration,
...angular_template,
...angular_template_blocks,
lang
]
