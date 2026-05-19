#!/bin/bash

set -e

module use /opt/spack-stack/envs/unified-env/modules/Core

module load stack-gcc
module load stack-openmpi

mpif90 -o hello.exe mpi_hello.f90

srun --mpi=pmix -N 3 --tasks-per-node=2 ./hello.exe | sort > hello.out
diff hello.out hello.baseline

srun -N 3 --tasks-per-node=2 ./hello.exe | sort > hello.out
diff hello.out hello.baseline
