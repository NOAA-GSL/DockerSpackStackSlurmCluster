#!/bin/bash

set -e

module use /opt/spack-stack/envs/unified-env/install/modulefiles/Core
module load stack-gcc
module load stack-openmpi
module load stack-python

mpif90 -o hello.exe mpi_hello.f90
srun -N 3 --tasks-per-node=2 hello.exe | sort > hello.out

diff hello.out hello.baseline
