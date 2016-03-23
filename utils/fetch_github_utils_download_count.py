#!/usr/bin/env python3

import requests


def fetch_download_count():
    response = requests.get('https://www.atom.io/api/packages/github-utils')
    data = response.json()

    print('The github-utils package has {} downloads'.format(data['downloads']))


if __name__ == '__main__':
    fetch_download_count()

