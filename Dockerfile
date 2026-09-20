FROM debian:bookworm-slim AS compiler
ARG ZIG_VERSION=0.14.1
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils inotify-tools && rm -rf /var/lib/apt/lists/*
RUN case "$TARGETARCH" in arm64) ARCH=aarch64 ;; amd64) ARCH=x86_64 ;; *) exit 1 ;; esac && curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-${ARCH}-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz && mkdir /opt/zig && tar -xJf /tmp/zig.tar.xz --strip-components=1 -C /opt/zig && rm /tmp/zig.tar.xz
ENV PATH="/opt/zig:${PATH}"
WORKDIR /app
CMD ["sh", "docker/watch.sh"]
