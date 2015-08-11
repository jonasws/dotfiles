'use babel';

import Shell from 'shell';

atom.commands.add('atom-workspace atom-text-editor', 'custom:open-karma', Shell.openExternal.bind(Shell, 'http://localhost:8080/debug.html'));
