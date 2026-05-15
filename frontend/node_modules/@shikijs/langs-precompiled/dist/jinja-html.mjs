import html from './html.mjs'

const lang = Object.freeze({displayName:"jinja-html",firstLineMatch:/^\{% extends ["'][^"']+["'] %\}/dgv,foldingStartMarker:/(<([Hh][Ee][Aa][Dd]|[Tt][Aa][Bb][Ll][Ee]|[Tt][Rr]|[Dd][Ii][Vv]|[Ssſ][Tt][Yy][Ll][Ee]|[Ssſ][Cc][Rr][Ii][Pp][Tt]|[Uu][Ll]|[Oo][Ll]|[Ff][Oo][Rr][Mm]|[Dd][Ll])\b[^\n]*?>|\{%\p{space}*(block|filter|for|if|macro|raw))/dgv,foldingStopMarker:/(<\/([Hh][Ee][Aa][Dd]|[Tt][Aa][Bb][Ll][Ee]|[Tt][Rr]|[Dd][Ii][Vv]|[Ssſ][Tt][Yy][Ll][Ee]|[Ssſ][Cc][Rr][Ii][Pp][Tt]|[Uu][Ll]|[Oo][Ll]|[Ff][Oo][Rr][Mm]|[Dd][Ll])\b[^\n]*?>|\{%\p{space}*(end(?:block|filter|for|if|macro|raw))\p{space}*%\})/dgv,name:"jinja-html",patterns:[{include:"source.jinja"},{include:"text.html.basic"}],scopeName:"text.html.jinja",embeddedLangs:["html"],aliases:undefined})

export default [
...html,
lang
]
