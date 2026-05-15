import angular_html from './angular-html.mjs'
import angular_template from './angular-template.mjs'

const lang = Object.freeze({injectTo:["source.ts.ng"],injectionSelector:"L:meta.decorator.ts -comment -text.html",name:"angular-inline-template",patterns:[{include:"#inlineTemplate"}],repository:{inlineTemplate:{begin:/(template)\p{space}*(:)/dgv,beginCaptures:{"1":{name:"meta.object-literal.key.ts"},"2":{name:"meta.object-literal.key.ts punctuation.separator.key-value.ts"}},end:/(?=[\,\}])/dgv,patterns:[{include:"#tsParenExpression"},{include:"#ngTemplate"}]},ngTemplate:{begin:/\p{space}*(["'\`\|])/dgvy,beginCaptures:{"1":{name:"string"}},contentName:"text.html.derivative.ng",end:/\1()/dgv,endCaptures:{"0":{name:"string"}},patterns:[{include:"text.html.derivative.ng"},{include:"template.ng"}]},tsParenExpression:{begin:/\p{space}*(\()/dgvy,beginCaptures:{"1":{name:"meta.brace.round.ts"}},end:/\)/dgv,endCaptures:{"0":{name:"meta.brace.round.ts"}},patterns:[{include:"#tsParenExpression"},{include:"#ngTemplate"}]}},scopeName:"inline-template.ng",displayName:undefined,embeddedLangs:["angular-html","angular-template"],aliases:undefined})

export default [
...angular_html,
...angular_template,
lang
]
