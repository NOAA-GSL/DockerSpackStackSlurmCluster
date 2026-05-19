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

# Building the Containers

To build the containers from source:

## Master and Node Containers

```bash
docker build -t ghcr.io/noaa-gsl/dockerspackstackslurmcluster/slurm-spack-stack-master:latest -f master/Dockerfile master/
docker build -t ghcr.io/noaa-gsl/dockerspackstackslurmcluster/slurm-spack-stack-node:latest -f node/Dockerfile node/
```

## Frontend Container

The frontend container requires a GitHub personal access token (PAT) with package write permissions to push built packages to the GitHub Container Registry build cache. Set your token in an environment variable and pass it as a secret during build:

```bash
export GITHUB_TOKEN=your_github_pat_here
docker build --progress=plain \
  --secret id=github_token,env=GITHUB_TOKEN \
  -t ghcr.io/noaa-gsl/dockerspackstackslurmcluster/slurm-spack-stack-frontend:latest \
  -f frontend/Dockerfile \
  frontend/
```

**Note:** The `--progress=plain` flag shows full build output. The frontend build compiles 355+ scientific software packages from source and can take several hours on first build. Subsequent builds use the cached packages from GHCR.

### Configuring Parallel Build Jobs

The frontend Dockerfile uses the `SPACK_BUILD_JOBS` build argument to control the number of parallel make jobs (`-j` flag) used when building each package (default: 8). This should match the number of CPU cores available:

**For 8-core systems (default):**
```bash
docker build --build-arg SPACK_BUILD_JOBS=8 ...
```

**For 16-core systems:**
```bash
docker build --build-arg SPACK_BUILD_JOBS=16 ...
```

**With Docker Compose:**
```bash
docker compose build --build-arg SPACK_BUILD_JOBS=16
```

You can also modify the default in `docker-compose.yml`:
```yaml
services:
  slurmfrontend:
    build:
      args:
        SPACK_BUILD_JOBS: 16  # Change from default 8
```

**Performance note:** Higher values speed up compilation of individual packages, especially large ones like ESMF, JEDI components, and NetCDF. However, on 32GB RAM systems, values above 8 may cause memory pressure during compilation of memory-intensive Fortran packages, potentially leading to swapping or OOM errors.

# Quick Start

To start the slurm cluster environment:
```
docker-compose -f docker-compose.yml up -d
```
To stop the cluster:
```
docker-compose -f docker-compose.yml stop
```
To check the cluster logs:
```
docker-compose -f docker-compose.yml logs -f
```
(stop logs with CTRL-c")

To check status of the cluster containers:
```
docker-compose -f docker-compose.yml ps
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
