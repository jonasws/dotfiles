'use babel';

import Shell from 'shell';

atom.commands.add('atom-workspace atom-text-editor', 'custom:open-karma', Shell.openExternal.bind(Shell, 'http://localhost:8080/debug.html'));

atom.commands.add('atom-workspace atom-text-editor', 'custom:toggle-emmet', () => {
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
