#!/bin/bash

set -euo pipefail
set -x

make build-cdrom

cp mister_linux.iso /repo-src/mister_linux.iso || cp mister_linux.iso /out/mister_linux.iso
