# Casys engineering toolchain
#
# One image carrying the full model-to-physics verification chain:
#   mcp-syson      SysML v2 models, constraints, part structure (z3 for solve)
#   mcp-build123d  parametric CAD as code (Python/OCCT)
#   mcp-calculix   FEA — Gmsh meshing + CalculiX solves
#
# The first argument selects the stateless HTTP server. The caller supplies
# its explicit port and hostname, for example: syson --port=3009 --hostname=0.0.0.0

# Ubuntu base rather than the Deno image's Debian trixie: calculix-ccx was
# dropped from trixie, while Ubuntu 24.04 carries ccx 2.21, gmsh 4.12 and z3.
# Deno itself is copied in as a static binary from the official image.
FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/superWorldSavior/engineering-toolchain"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.title="Casys engineering toolchain"
LABEL org.opencontainers.image.description="One image for mcp-syson, mcp-build123d and mcp-calculix with z3, Python/OCCT, Gmsh and CalculiX bundled."

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    BUILD123D_EXPORT_DIR=/exports \
    CALCULIX_RUNS_DIRECTORY=/var/lib/mcp-calculix-runs

COPY --from=denoland/deno:bin-2.9.4 /deno /usr/local/bin/deno

# System backends: z3 (constraint solving), gmsh + ccx (FEA), python (CAD)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      python3 \
      python3-pip \
      gmsh \
      calculix-ccx \
      z3 \
    && rm -rf /var/lib/apt/lists/*

# build123d pulls cadquery-ocp-novtk (~150 MB) — the heavyweight layer,
# kept separate so apt changes do not invalidate it. Pin its public API release
# just like the MCP wrapper so the primary geometry runtime cannot drift.
# pip is a build tool: drop it after the wheel is installed.
RUN pip3 install --no-cache-dir --break-system-packages build123d==0.11.1 \
    && apt-get purge -y python3-pip \
    && apt-get autoremove -y --purge \
    && rm -rf /root/.cache /tmp/*

RUN mkdir -p /exports /work /var/lib/mcp-calculix-runs

# Pinned server versions, Deno lock and dependency-age policy are versioned
# together. mcp-server is not remapped: each JSR package keeps the version it
# published against (syson 0.24.0, build123d 0.24.1, calculix 0.26.0).
WORKDIR /opt/engineering-toolchain
COPY deno.json deno.lock ./
RUN deno cache --frozen \
      jsr:@casys/mcp-syson@0.6.0/server \
      jsr:@casys/mcp-build123d@0.5.0/server \
      jsr:@casys/mcp-calculix@0.7.0/server \
      jsr:@casys/mcp-build123d@0.5.0 \
    && deno eval --cached-only --frozen \
      'import { runCadScript } from "jsr:@casys/mcp-build123d@0.5.0"; const result = await runCadScript("from build123d import Box\nresult = Box(1, 1, 1)"); if (Math.abs(result.metrics.volume_mm3 - 1) > 1e-9) throw new Error("build123d package smoke test failed");' \
    && rm -rf /tmp/* /exports/*

COPY --chmod=0755 entrypoint.sh /entrypoint.sh
WORKDIR /work
ENTRYPOINT ["/entrypoint.sh"]
