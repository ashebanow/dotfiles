#!/usr/bin/env python

# This script fetches the latest Bing wallpaper
#
# TODO: needs to be run as a cron job

import requests
import json
import subprocess
import shutil
import os

REGION = 'en-US'

BASE_URL = f'https://bing.biturl.top/?resolution=UHD&format=json&index=0&mkt={REGION}'
BASE_PATH = '~/Pictures/wallpapers/'
ARCHIVE_PATH = BASE_PATH + 'bing/'

# fetch the wallpaper metadata
u = requests.get(BASE_URL).json()

# download the wallpaper and save it to archive
r = requests.get(u['url'], stream=True)
name = u['url'].split('=')[-1]

filePath = os.path.join(ARCHIVE_PATH, name)
with open(filePath, 'wb') as file:
    for chunk in r.iter_content(chunk_size=8192):
        file.write(chunk)

# TODO: make the hyprpanel equivalent to this hyprpaper setup
# copy wallpaper to the current wallpaper path
# currentPath = os.path.join(BASE_PATH, 'current.jpg')
# shutil.copy(filePath, currentPath)
# subprocess.run(['hyprctl', 'hyprpaper', 'reload', ',' + currentPath])
