'use babel';

import Shell from 'shell';

atom.commands.add('atom-workspace atom-text-editor', 'custom:open-karma', Shell.openExternal.bind(Shell, 'http://localhost:8080/debug.html'));

atom.commands.add('atom-workspace', 'custom:toggle-emmet', () => {
  if (atom.packages.isPackageDisabled('emmet')) {
    let enabled = atom.packages.enablePackage('emmet');
    if (enabled !== null) {
      atom.notifications.addInfo('Emmet enabled')
    }
  } else {
    let disabled = atom.packages.disablePackage('emmet');
    if (disabled !== null) {
      atom.notifications.addInfo('Emmet disabled');
    }
  }
});


getCursors = () => {
  let editor = atom.workspace.getActiveTextEditor();
  return editor ? editor.getCursors() : [];
};

atom.commands.add('atom-text-editor', 'custom:move-to-beginning-of-screen-line', () => {
  let cursors = getCursors();

  if (cursors.length === 1) {
    cursors[0].moveToBeginningOfScreenLine();
  }
});

atom.commands.add('atom-text-editor', 'custom:move-to-end-of-screen-line', () => {
  let cursors = getCursors();

  if (cursors.length === 1) {
    cursors[0].moveToEndOfScreenLine();
  }
});
