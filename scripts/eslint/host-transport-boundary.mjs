/**
 * Keep native SDK imports behind the mobile host boundary without replacing
 * the repository's existing restricted-import or restricted-syntax rules.
 * @type {import('eslint').Rule.RuleModule}
 */
export const hostTransportBoundary = {
  meta: {
    type: 'problem',
    schema: [],
    messages: {
      adapterOnly: 'Load native SDKs inside host-runtime/adapters and use ~/host-runtime in business code.',
    },
  },
  create(context) {
    function check(source) {
      if (typeof source?.value !== 'string')
        return
      if (source.value.startsWith('@capacitor/') || source.value === '@yunlefun/capacitor-storekit')
        context.report({ node: source, messageId: 'adapterOnly' })
    }
    return {
      ImportDeclaration: node => check(node.source),
      ImportExpression: node => check(node.source),
      ExportNamedDeclaration: node => check(node.source),
      ExportAllDeclaration: node => check(node.source),
    }
  },
}
