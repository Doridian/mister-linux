#!/bin/sh

docker build -t misterlin .
docker run --rm -it -v "misterlinux_repo:/src/mister" -v "${pwd}:/repo-src" misterlin
