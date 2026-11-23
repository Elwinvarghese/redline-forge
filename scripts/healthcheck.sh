#!/bin/sh
set -eu
python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/', timeout=5)"
