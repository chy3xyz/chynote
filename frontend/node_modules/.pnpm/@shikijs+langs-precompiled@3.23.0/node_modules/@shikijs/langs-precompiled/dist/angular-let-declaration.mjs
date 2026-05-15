import angular_expression from './angular-expression.mjs'

const lang = Object.freeze({injectTo:["text.html.derivative","text.html.derivative.ng","source.ts.ng"],injectionSelector:"L:text.html -comment -expression.ng -meta.tag -source.css -source.js",name:"angular-let-declaration",patterns:[{include:"#letDeclaration"}],repository:{letDeclaration:{begin:/(@let)\p{space}+([\$_\p{Alpha}][\$_\p{Alpha}\p{Nd}]*)\p{space}*(=)?/dgv,beginCaptures:{"1":{name:"storage.type.ng"},"2":{name:"variable.other.constant.ng"},"3":{name:"keyword.operator.assignment.ng"}},end:/(?<=;)/dgv,name:"meta.definition.variable.ng",patterns:[{include:"#letInitializer"}]},letInitializer:{begin:/\p{space}*/dgv,beginCaptures:{"0":{name:"keyword.operator.assignment.ng"}},contentName:"meta.definition.variable.initializer.ng",end:/;/dgv,endCaptures:{"0":{name:"punctuation.terminator.statement.ng"}},patterns:[{include:"expression.ng"}]}},scopeName:"template.let.ng",displayName:undefined,embeddedLangs:["angular-expression"],aliases:undefined})

export default [
...angular_expression,
lang
]
