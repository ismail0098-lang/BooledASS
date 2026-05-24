# Stage 1: Build BooledASS (Z3)
FROM ubuntu:24.04 AS builder

# Install build dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    g++ \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy solver source
WORKDIR /workspace/BooledASS
COPY . .

# Configure and build
RUN mkdir build && cd build && \
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. && \
    ninja -j$(nproc)

# Stage 2: Minimal runtime image
FROM ubuntu:24.04

# Copy binary from builder
COPY --from=builder /workspace/BooledASS/build/z3 /usr/local/bin/z3

# Set runtime configuration
ENTRYPOINT ["/usr/local/bin/z3"]
CMD ["-smt2"]
