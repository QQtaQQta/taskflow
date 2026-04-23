# syntax=docker/dockerfile:1.7

# ──────────────────────────────────────────────────────────────────────────────
# Build stage: full Swift toolchain. Produces a single stripped, release-mode
# binary that statically embeds the Swift standard library so the runtime
# image can stay tiny (no Swift toolchain / runtime .so files needed at all).
# ──────────────────────────────────────────────────────────────────────────────
FROM swift:6.3.1 AS build
WORKDIR /build

# Resolve dependencies first for better layer caching.
COPY Package.swift Package.resolved ./
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/root/.swiftpm \
    swift package resolve

# Copy only the code actually needed to build the `Run` product. Tests are
# intentionally excluded from the build context to reduce disk/RAM pressure;
# SwiftPM however still validates the test target path, so we seed an empty
# stub directory so `swift build` does not refuse to plan.
COPY Sources ./Sources
COPY Public ./Public
RUN mkdir -p Tests/ApplicationTests \
    && : > Tests/ApplicationTests/.keep

# Compile release. `--static-swift-stdlib` removes the ~200 MB of Swift
# runtime .so dependencies from the deploy image. We also strip debug
# symbols — the stripped binary typically shrinks by 30–40%.
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/root/.swiftpm \
    --mount=type=cache,target=/build/.build \
    swift build -c release --product Run --static-swift-stdlib \
    && install -m 0755 "$(swift build -c release --show-bin-path)/Run" /build/Run \
    && strip --strip-unneeded /build/Run \
    && mkdir -p /staging/app \
    && cp /build/Run /staging/app/Run \
    && cp -R /build/Sources/Application/Resources /staging/app/Resources \
    && cp -R /build/Public /staging/app/Public

# ──────────────────────────────────────────────────────────────────────────────
# Runtime stage: minimal Ubuntu 24.04 base (matches the Swift 6.3.1 build
# toolchain so glibc/libstdc++ symbol versions align). Only the system
# libraries the binary links against (libstdc++, libgcc, libc, libxml2,
# libcurl) are installed — everything Swift is already embedded in the
# binary, so no ~250 MB of Swift runtime .so files are pulled in.
# ──────────────────────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS runtime

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --no-install-recommends \
        ca-certificates \
        tzdata \
        libxml2 \
        libcurl4 \
        busybox \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && useradd --system --create-home --uid 10001 --home-dir /app vapor

WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging/app /app

USER vapor
EXPOSE 8080

# busybox ships `wget` (~1 MB), so the runtime image avoids pulling the
# larger `curl` package just for the health probe.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
    CMD busybox wget -q -O - http://127.0.0.1:8080/api/v1/health >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/app/Run"]
