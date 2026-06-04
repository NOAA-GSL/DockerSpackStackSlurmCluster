[![Docker Slurm](https://github.com/NOAA-GSL/DockerSpackStackSlurmCluster/actions/workflows/docker.yml/badge.svg?branch=main)](https://github.com/NOAA-GSL/DockerSpackStackSlurmCluster/actions/workflows/docker.yml)

# Slurm Cluster with spack-stack in Ubuntu Docker images using Docker Compose

This is a fully functional Slurm cluster with
[spack-stack](https://spack-stack.readthedocs.io/en/latest/) installed inside a Docker container.

This work is an adaptation of the work done by Rodrigo Ancavil del Pino:

https://medium.com/analytics-vidhya/slurm-cluster-with-docker-9f242deee601

There are three containers:

* A frontend container that acts as a Slurm cluster login node.
  Spack-stack is installed on the frontend in /opt which is mounted
  across the cluster as a shared volume using docker compose
* A master container that acts as a Slurm master controller node
* A node container that acts as a Slurm compute node

These containers are launched using Docker Compose to build
a fully functioning Slurm cluster.  A `docker-compose.yml`
file defines the cluster, specifying ports and volumes to
be shared.  Multiple instances of the node container can be
added to `docker-compose.yml` to create clusters of different
sizes.  The cluster behaves as if it were running on multiple
nodes even if the containers are all running on the same host
machine.

# Image tags and base selection

Published images are tagged by Ubuntu version + spack-stack version:

* `ubuntu-26.04-spack-stack-2.1.0` (also published as `latest`)
* `ubuntu-24.04-spack-stack-2.1.0`

Internally each variant pulls from the
[NOAA-GSL/DockerSlurmCluster](https://github.com/NOAA-GSL/DockerSlurmCluster)
base registry at the matching `ubuntu-<UBUNTU_VERSION>-slurm-<SLURM_VERSION>` tag.
The base image's slurm version is implicit -- consumers of these images interact
with the slurm tooling that came with the base, plus the spack-stack scientific
software stack layered on top.

A separate per-(ubuntu, spack-stack) OCI buildcache repo (e.g.
`ghcr.io/noaa-gsl/dockerspackstackslurmcluster/buildcache-ubuntu-26.04-spack-stack-2.1.0`)
holds binary artifacts so rebuilds reuse cached packages instead of recompiling
from source. Caches are split per OS to prevent cross-OS spec contamination
during concretization.

## Configuring versions

The project root contains a `.env` file consumed by `docker compose`:

```bash
UBUNTU_VERSION=26.04
SLURM_VERSION=25.11.5
SPACK_STACK_VERSION=2.1.0
```

To run against the 24.04 base for one invocation without editing the file:

```bash
UBUNTU_VERSION=24.04 docker compose up -d --pull never
```

# Building the Containers

## Quickest path: docker compose

`docker compose build` reads `.env` and constructs the full set of build args
automatically. To build all three containers (frontend, master, node) for the
default Ubuntu version:

```bash
docker compose build
```

Or just one:

```bash
docker compose build slurmfrontend
```

To build for a non-default Ubuntu version:

```bash
UBUNTU_VERSION=24.04 docker compose build slurmfrontend
```

### GitHub PAT for buildcache push

A GitHub personal access token (PAT) is only required if you want the build to
**push** newly-built spack packages back to the OCI buildcache (autopush) --
which is what CI and the original maintainer's builds do to keep the cache
populated. For most local development, where you just want to *consume*
artifacts the cache already has, no PAT is needed.

The frontend Dockerfile only configures autopush when the docker secret
`github_token` is present *and non-empty*. Compose accepts an unset or empty
`GITHUB_TOKEN` environment variable (the secret simply becomes an empty file
inside the build), so pull-only builds work without setting anything:

```bash
# Pull-only build: reads from the public buildcache, never pushes
docker compose build slurmfrontend
```

For push-capable builds, set the PAT before invoking compose:

```bash
export GITHUB_TOKEN=your_github_pat_here   # PAT with write:packages on the GHCR registry
docker compose build slurmfrontend
```

Note: this assumes the buildcache repo on GHCR is **public** (which is the
case for the upstream NOAA-GSL caches). If you maintain a fork with a private
cache, you'll need a PAT with read permission on the cache repo even for
pull-only builds.

## Direct buildx invocation

Equivalent build command for the frontend, useful when you want full control
(`--no-cache`, `--progress=plain`, custom tags) without going through compose:

```bash
export GITHUB_TOKEN=your_github_pat_here
docker buildx build \
  --progress=plain \
  --pull \
  --secret id=github_token,env=GITHUB_TOKEN \
  --build-arg SPACK_BUILD_JOBS=8 \
  --build-arg BASE_IMAGE_TAG=ubuntu-26.04-slurm-25.11.5 \
  --build-arg UBUNTU_VERSION=26.04 \
  --build-arg SPACK_STACK_VERSION=2.1.0 \
  -t ghcr.io/noaa-gsl/dockerspackstackslurmcluster/slurm-spack-stack-frontend:ubuntu-26.04-spack-stack-2.1.0 \
  -f frontend/Dockerfile \
  frontend/
```

The frontend build compiles ~355 scientific software packages and can take
many hours on first build from an empty buildcache. Subsequent builds reuse
cached packages from GHCR and finish much faster.

## Configuring Parallel Build Jobs

`SPACK_BUILD_JOBS` controls the number of parallel make jobs (`-j` flag) used
when building each package (default: 8). Match it to the CPU count of your
build machine:

```bash
docker buildx build --build-arg SPACK_BUILD_JOBS=16 ...
# or
docker compose build --build-arg SPACK_BUILD_JOBS=16
```

You can also change the default in `docker-compose.yml`:

```yaml
services:
  slurmfrontend:
    build:
      args:
        SPACK_BUILD_JOBS: 16  # Change from default 8
```

**Performance note:** higher values speed up compilation of individual
packages, especially large ones like ESMF, JEDI components, and NetCDF. On
32GB RAM systems values above 8 may cause memory pressure during compilation
of memory-intensive Fortran packages, potentially leading to swapping or OOM
errors.

# Quick Start

To start the slurm cluster environment (default Ubuntu 26.04):
```
docker compose -f docker-compose.yml up -d --pull never
```

For 24.04:
```
UBUNTU_VERSION=24.04 docker compose -f docker-compose.yml up -d --pull never
```

The frontend container takes several minutes on first launch (it populates the
shared `opt-vol` volume with the spack-stack install). Healthchecks ensure the
master and nodes wait for the frontend before starting.

### Switching `UBUNTU_VERSION` between runs

Docker named volumes are not auto-rebuilt when you change the image they're
attached to. To switch from 26.04 to 24.04 (or vice versa) on the same host,
you must explicitly remove the existing `home-vol` and `opt-vol` first:

```
docker compose down -v   # the -v flag deletes the named volumes
UBUNTU_VERSION=24.04 docker compose up -d --pull never
```

Without `-v`, the new container will mount the previous run's `/opt`, which
contains spack-built binaries linked against the *previous* OS's glibc. The
cluster will appear to start fine but `srun` of any spack-built executable will
fail with `GLIBC_X.YZ not found`.

To stop the cluster:
```
docker compose -f docker-compose.yml stop
```
To check the cluster logs:
```
docker compose -f docker-compose.yml logs -f
```
(stop logs with CTRL-c)

To check status of the cluster containers:
```
docker compose -f docker-compose.yml ps
```
To check status of Slurm:
```
docker exec spack-stack-frontend sinfo
```
To run a Slurm job:
```
docker exec spack-stack-frontend srun hostname
```
To obtain an interactive shell in the container:
```
docker exec -it spack-stack-frontend bash -l
```

# Loading and using spack-stack

First, obtain a login shell in the container:
```
docker exec -it spack-stack-frontend bash -l
```

Next, load the spack-stack base environment:

```
module use /opt/spack-stack/envs/unified-env/modules/Core
module load stack-gcc
module load stack-openmpi
```

Once the basic spack-stack modules are loaded, you can choose from multiple spack-stack environments for different purposes.

For example:

* FV3:
  ```
  module load jedi-fv3-env
  ```

* MPAS
  ```
  module load jedi-mpas-env
  ```
