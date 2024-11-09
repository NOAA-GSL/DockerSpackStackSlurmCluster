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

First, run a login shell in the container:
```
docker exec -it spack-stack-frontend bash -l
```

Next, load the spack-stack base environment:

```
module use /opt/spack-stack/envs/unified-env/install/modulefiles/Core
module load stack-gcc
module load stack-openmpi
module load stack-python
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
