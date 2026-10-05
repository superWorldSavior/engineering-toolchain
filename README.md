# Casys engineering toolchain

One Docker image carrying the full **model-to-physics verification chain** —
zero native installs:

| Server                                                       | What it does                                                 | System deps bundled     |
| ------------------------------------------------------------ | ------------------------------------------------------------ | ----------------------- |
| [`mcp-syson`](https://github.com/superWorldSavior/mcp-syson)         | SysML v2 models, constraints, part structure                 | z3 (constraint solving) |
| [`mcp-build123d`](https://github.com/superWorldSavior/mcp-build123d) | parametric CAD as code, exact mass properties, STEP/STL/GLTF | Python + build123d/OCCT |
| [`mcp-calculix`](https://github.com/superWorldSavior/mcp-calculix)   | FEA — meshing + CalculiX solves, including recorded static   | Gmsh + CalculiX         |

The first argument selects a **stateless HTTP** server. Callers must pass its
port and hostname explicitly; the image exposes HTTP only.

```bash
docker run --rm -p 127.0.0.1:3009:3009 ghcr.io/casys-ai/engineering-toolchain:0.5.0 \
  syson --port=3009 --hostname=0.0.0.0
docker run --rm -p 127.0.0.1:3014:3014 ghcr.io/casys-ai/engineering-toolchain:0.5.0 \
  build123d --port=3014 --hostname=0.0.0.0
docker run --rm -p 127.0.0.1:3015:3015 ghcr.io/casys-ai/engineering-toolchain:0.5.0 \
  calculix --port=3015 --hostname=0.0.0.0
```

Anonymous `docker pull` needs the GHCR package to be **public**. The repo is
public; the package starts private and is flipped once in the GitHub package
settings.

## The whole chain in one command

```bash
docker compose up -d
```

brings up SysON (the SysML v2 modeler, http://localhost:8180) plus the three MCP
servers over stateless HTTP (ports 3009 / 3014 / 3015, loopback only). Every MCP
endpoint is `/mcp`, emits complete responses without an MCP session, and
publishes its registered viewer resources through `resources/list`.
`mcp-build123d` and `mcp-calculix` share the `exports` volume, so a STEP
exported by `build123d_export` is immediately readable by
`calculix_solve_static` at `/exports/<name>.step`. Recorded CalculiX runs persist
on the `calculix-runs` volume.

Notes that matter:

- **SYSON_URL** — the Compose service uses `http://syson-app:8080`; an alternate
  deployment must point this variable at its SysON instance.
- **Shared volume** — the same named volume (`exports`) mounted in build123d and
  calculix is what lets a STEP flow between them; pass `/exports/<name>.step` as
  `step_path`.
- **Recorded FEA** — mount `CALCULIX_RUNS_DIRECTORY` (Compose does this) so
  `calculix_solve_static_recorded` and `calculix_run_get` survive a restart.
- **HTTP inside a container** — the servers bind loopback by default. Compose
  passes `--hostname=0.0.0.0` so its loopback-only host mappings can reach them.

## Version pinning

The image pins exact server versions — `@casys/mcp-syson@0.6.0`,
`@casys/mcp-build123d@0.5.0`, and `@casys/mcp-calculix@0.7.0`. `deno.json` keeps
a P1D dependency-age quarantine. Deno scopes an age exclusion by package name
rather than package version, so the exclusions are limited to five audited Casys
names. Each server keeps the `@casys/mcp-server` release it published against
(0.24.0 / 0.24.1 / 0.26.0); the import map does not force one version on all
three. `@casys/constraint-solver@0.1.0` stays pinned for SysON. The runtime is
cached-only. The base is Ubuntu 24.04 (Debian trixie dropped `calculix-ccx`),
with the Deno binary copied from the official image. The underlying Python CAD
runtime is pinned to `build123d@0.11.1`.

The `0.5.0` image is published for `linux/amd64` and `linux/arm64`. Compose
selects the native architecture for the toolchain services. SysON itself remains
amd64-only and is emulated on Apple Silicon.

## Security model

`build123d` executes arbitrary Python and `calculix` runs solvers on
caller-named files — inside the container, which contains them but is not a
strong sandbox (mounted volumes are writable, the network is reachable unless
restricted). The trust model is unchanged from running the servers natively:
only expose them to callers you trust. Add `--network=none` to
build123d/calculix deployments if their scripts need no network — the tools
themselves never do.

## Build locally

```bash
docker build -t engineering-toolchain:local-0.5.0 .
docker run --rm engineering-toolchain:local-0.5.0 calculix --port=3015 --hostname=0.0.0.0
```

## License

MIT
