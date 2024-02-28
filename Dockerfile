FROM alpine

RUN apk add --no-cache bash curl jq wget nano make git patch gcc g++ musl-dev

RUN mkdir -p /src/musl-cross-make
WORKDIR /src/musl-cross-make
RUN git init && \
    git remote add origin 'https://github.com/richfelker/musl-cross-make.git' && \
    git fetch --depth=1 origin 'fe915821b652a7fa37b34a596f47d8e20bc72338' && \
    git reset --hard 'fe915821b652a7fa37b34a596f47d8e20bc72338'
COPY docker/config.mak /src/musl-cross-make/config.mak
RUN make extract_all
RUN make install -j$(nproc)

ENV PATH="/opt/musl-cross/bin:${PATH}"
RUN apk add --no-cache flex bc perl bison quilt rsync python3 nasm xz dosfstools mtools ncurses-terminfo-base genext2fs squashfs-tools kmod ncdu linux-headers cpio ncurses-dev util-linux-dev libuuid cdrkit
ENV OBJDUMP=i486-linux-musl-objdump

VOLUME /repo-src
VOLUME /repo-dist
VOLUME /repo-stamp

RUN mkdir -p /src/mister-linux
WORKDIR /src/mister-linux

COPY --chmod=755 docker/init.sh /init.sh
COPY --chmod=755 docker/build.sh /usr/local/bin/cdbuild
ENTRYPOINT [ "/init.sh" ]

VOLUME /out

COPY docker/dockerbuild.sh /dockerbuild.sh
RUN /bin/bash /dockerbuild.sh && rm -f /dockerbuild.sh
