'use babel';

import Shell from 'shell';

const togglePackage = packageName => () => {
    if (atom.packages.isPackageDisabled(packageName)) {
      const enabled = atom.packages.enablePackage(packageName);
      if (enabled !== null) {
        atom.notifications.addInfo(`${packageName} enabled`);
      }
    } else {
      const disabled = atom.packages.disablePackage(packageName);
      if (disabled !== null) {
        atom.notifications.addInfo(`${packageName} disabled`);
      }
    }
  };

const getCursors = () => {
  const editor = atom.workspace.getActiveTextEditor();
  return editor ? editor.getCursors() : [];
};

const setXslGrammar = () => {
  const xslGrammar = atom.grammars.grammarForScopeName('text.xml.xsl');
  atom.workspace.getActiveTextEditor().setGrammar(xslGrammar);
};

atom.commands.add('atom-workspace atom-text-editor', 'custom:set-xsl-grammar', setXslGrammar);

atom.commands.add('atom-workspace atom-text-editor', 'custom:open-karma', Shell.openExternal.bind(Shell, 'http://localhost:8080/debug.html'));

atom.commands.add('atom-workspace', 'custom:toggle-emmet', togglePackage('emmet'));

atom.commands.add('atom-workspace', 'custom:toggle-autocomplete-snippets', togglePackage('autocomplete-snippets'));

atom.commands.add('atom-text-editor', 'custom:move-to-beginning-of-screen-line', () => {
  const cursors = getCursors();

  if (cursors.length === 1) {
    cursors[0].moveToBeginningOfScreenLine();
  }
});

atom.commands.add('atom-text-editor', 'custom:move-to-end-of-screen-line', () => {
  const cursors = getCursors();

  if (cursors.length === 1) {
    cursors[0].moveToEndOfScreenLine();
  }
});

atom.commands.add('atom-text-editor', 'custom:toggle-wrap-guide', togglePackage('wrap-guide'));

atom.commands.add('atom-text-editor', 'custom:toggle-autosave', togglePackage('autosave'))
