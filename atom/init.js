'use babel';

import Shell from 'shell';

function togglePackage(packageName) {

  if (atom.packages.isPackageDisabled(packageName)) {
    let enabled = atom.packages.enablePackage(packageName);
    if (enabled !== null) {
      atom.notifications.addInfo(`${packageName} enabled`);
    }
  } else {
    let disabled = atom.packages.disablePackage(packageName);
    if (disabled !== null) {
      atom.notifications.addInfo(`${packageName} disabled`);
    }
  }

}

function getCursors() {
  let editor = atom.workspace.getActiveTextEditor();
  return editor ? editor.getCursors() : [];
}

atom.commands.add('atom-workspace atom-text-editor', 'custom:open-karma', Shell.openExternal.bind(Shell, 'http://localhost:8080/debug.html'));

atom.commands.add('atom-workspace', 'custom:toggle-emmet', togglePackage.bind(undefined, 'emmet'));

atom.commands.add('atom-workspace', 'custom:toggle-autocomplete-snippets', togglePackage.bind(undefined, 'autocomplete-snippets'));

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
