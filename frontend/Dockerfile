FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-frontend:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

SHELL ["/bin/bash", "-c"]

# Copy patch files into /tmp for later use
COPY cc.patch.aarch64 /tmp
COPY cc.patch.x86_64 /tmp
COPY openmpi.package.py.patch.aarch64 /tmp
COPY openmpi.package.py.patch.x86_64 /tmp

RUN --mount=type=secret,id=access_key_id --mount=type=secret,id=secret_access_key --mount=type=secret,id=session_token <<EOF
  set -e

  # Install OS packages
  apt-get -y update
  apt-get -y install --no-install-recommends \
        awscli \
        bc \
        build-essential \
        ca-certificates \
        curl \
	emacs \
        file \
        g++ \
        gcc \
        gfortran \
        git \
        gnupg2 \
        iproute2 \
        locales \
        make \
        mercurial \
        python3 \
        python3-pip \
        python3-setuptools \
        subversion \
	tcl-dev \
        unzip \
        zstd
  pip3 install boto3
  rm -rf /var/lib/apt/lists/*

  
  # Install Lua
  wget https://sourceforge.net/projects/lmod/files/lua-5.1.4.9.tar.bz2
  tar xvfj lua-5.1.4.9.tar.bz2
  pushd lua-5.1.4.9
  ./configure --prefix=/usr
  make -j 4
  make install
  popd
  
  # Install Lmod
  git clone --recursive https://github.com/TACC/Lmod.git
  pushd Lmod
  ./configure --prefix=/usr
  make -j 4
  make install
  echo "source /usr/lmod/lmod/init/bash" >> /etc/bash.bashrc
  popd
  
  # Cleanup
  rm -rf lua* Lmod
  
  # Install spack-stack and setup environment
  cd /opt
  git clone -b release/1.8.0 --recurse-submodules https://github.com/jcsda/spack-stack.git
  pushd spack-stack
  . ./setup.sh

  # Patch spack for correct builds of openmpi and openblas (on arm64)
  pushd spack
  mv /tmp/cc.patch.$(uname -m) cc.patch
  mv /tmp/openmpi.package.py.patch.$(uname -m) openmpi.package.py.patch
  patch -f -p0 < openmpi.package.py.patch
  patch -f -p0 < cc.patch
  popd

  # Create the unified environment and activate it
  spack stack create env --site linux.default --template unified-dev --name unified-env --compiler gcc
  pushd envs/unified-env
  spack env activate .

  # Add a read-only buildcache mirror
  spack mirror add --s3-access-key-id "" --s3-access-key-secret "" s3_spack_stack_buildcache_ro s3://chiltepin-us-east-2/spack-stack/

  # Add an autopush buildcache mirror if credentials were provided
  if [ -f /run/secrets/access_key_id ]; then
    export AWS_ACCESS_KEY_ID=$(cat /run/secrets/access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(cat /run/secrets/secret_access_key)
    export AWS_SESSION_TOKEN=$(cat /run/secrets/session_token)
    spack mirror add --s3-access-key-id $AWS_ACCESS_KEY_ID --s3-access-key-secret $AWS_SECRET_ACCESS_KEY --s3-access-token $AWS_SESSION_TOKEN --autopush --unsigned s3_spack_stack_buildcache_rw s3://chiltepin-us-east-2/spack-stack/
  fi

  # Find external packages
  export SPACK_SYSTEM_CONFIG_PATH="$PWD/site"
  spack external find --scope system \
  --exclude cmake \
  --exclude curl \
  --exclude openssl \
  --exclude openssh \
  --exclude python
  spack external find --scope system wget
  spack compiler find --scope system
  unset SPACK_SYSTEM_CONFIG_PATH

  # Set compiler and MPI provider and tweak a few package configs
  spack config add "packages:all:compiler:[gcc@11.4.0]"
  spack config add "packages:all:providers:mpi:[openmpi@4.1.6]"
  spack config add "packages:fontconfig:variants:+pic"
  spack config add "packages:pixman:variants:+pic"
  spack config add "packages:cairo:variants:+pic"
  
  # Modify the configuration to build openmpi with slurm and PMI support
  spack config --scope env:/opt/spack-stack/envs/unified-env:common add "packages:openmpi:require:~internal-hwloc +two_level_namespace schedulers=slurm +pmi"

  # Add Slurm as an external package for use as a dependency for openmpi
  echo "  slurm:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml
  echo "    externals:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml
  echo "    - spec: slurm@23.11.7" >> /opt/spack-stack/envs/unified-env/site/packages.yaml
  echo "      prefix: /usr" >> /opt/spack-stack/envs/unified-env/site/packages.yaml
  echo "    buildable: false" >> /opt/spack-stack/envs/unified-env/site/packages.yaml

  # Make sure we use Lmod modules
  sed -i 's/tcl/lmod/g' site/modules.yaml
  sed -i 's/tcl/lmod/g' common/modules.yaml

  # Remove unwanted path prefixes for modules
  sed -i 's:{^mpi.name}/{^mpi.version}/{compiler.name}/{compiler.version}/{name}:{name}:' common/modules.yaml
  sed -i 's:{compiler.name}/{compiler.version}/{name}:{name}:' common/modules.yaml

  # Concretize the environment
  spack concretize 2>&1 | tee log.concretize
  spack mirror list

  # Install the environment, use autopush buildcache if credentials were provided
  spack install --no-check-signature # 2>&1 | tee log.install
  if [ -f /run/secrets/access_key_id ]; then  
    spack buildcache update-index s3_spack_stack_buildcache_rw
  fi

  # Generate modules
  source /usr/lmod/lmod/init/bash
  spack module lmod refresh -y
  spack stack setup-meta-modules

  # Cleanup unneccessary packages
  spack gc -y

  # Strip binaries to save some space
  find -L  /opt/spack-stack/envs/unified-env/install/gcc/11.4.0/* -type f -exec readlink -f '{}' \; | \
    xargs file -i | \
    grep 'charset=binary' | \
    grep 'x-executable\|x-archive\|x-sharedlib' | \
    awk -F: '{print $1}' | xargs strip -s

  # Cleanup unneeded .spack directories
  find /opt/spack-stack/envs/unified-env/install/gcc/11.4.0 -name .spack -type d -print0 | xargs -0 rm -rf "{}"
  rm -rf ~/.spack 

  # Cleanup /tmp
  rm -f /tmp/*
EOF
