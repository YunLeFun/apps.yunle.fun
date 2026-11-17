/**
 * Prevent reintroducing the retired bridge into browser code without replacing
 * the repository's existing restricted-import or restricted-syntax rules.
 * @type {import('eslint').Rule.RuleModule}
 */
export const hostTransportBoundary = {
  meta: {
    type: 'problem',
    schema: [],
    messages: {
      adapterOnly: 'Capacitor and Cordova are retired; browser code uses Web APIs.',
    },
  },
  create(context) {
    function check(source) {
      if (typeof source?.value !== 'string')
        return
      if (source.value.startsWith('@capacitor/') || source.value.startsWith('cordova-') || source.value === '@yunlefun/capacitor-storekit')
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
