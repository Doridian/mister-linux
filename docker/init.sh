#!/bin/bash

set -euo pipefail
set -x

if [ -d /repo-src/.git ];
then
    rsync -a /repo-src/ /src/mister-linux/ --exclude=out --exclude=src --exclude=src --exclude=stamp
else
    git clone https://github.com/Doridian/mister-linux.git /src/mister-linux
fi
cd /src/mister-linux
mkdir -p dist out src stamp

make download-all

exec /bin/bash "$@"
