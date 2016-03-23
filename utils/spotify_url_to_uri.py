#!/usr/bin/env python
from __future__ import print_function

import re
import sys

spotify_url = sys.argv[1]
matches = re.match(r'https://play\.spotify\.com/([/\w]+)', spotify_url)

uri_type, resource_identifier = matches.group(1).split('/')
print('spotify:{}:{}'.format(uri_type, resource_identifier))
