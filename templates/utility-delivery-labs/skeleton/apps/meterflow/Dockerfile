# syntax=docker/dockerfile:1

# Build for the target platform from any host (Apple silicon, Raspberry Pi, x86 CI runners).
FROM --platform=$BUILDPLATFORM golang:1.24 AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
      go build -trimpath -ldflags="-s -w" -o /out/headend ./cmd/headend && \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
      go build -trimpath -ldflags="-s -w" -o /out/meter-sim ./cmd/meter-sim

# Runtime image: no shell, no package manager, nothing to write to.
# It runs as any non-root UID, so OpenShift's restricted-v2 SCC can assign a random one (ADR-002).
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/ /usr/local/bin/
USER 65532:65532
EXPOSE 8080 9090
ENTRYPOINT ["/usr/local/bin/headend"]
