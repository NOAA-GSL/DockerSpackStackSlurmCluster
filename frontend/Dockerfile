FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-frontend:latest AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

SHELL ["/bin/bash", "-c"]

# Install OS packages
RUN apt-get -y update \
 && apt-get -y install --no-install-recommends \
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
        tcsh \
        unzip \
        zstd \
 && pip3 install boto3 \
 && rm -rf /var/lib/apt/lists/*

# Install Lua and Lmod
RUN wget https://sourceforge.net/projects/lmod/files/lua-5.1.4.9.tar.bz2 \
 && tar xvfj lua-5.1.4.9.tar.bz2 \
 && pushd lua-5.1.4.9 \
 && ./configure --prefix=/usr \
 && make -j 4 \
 && make install \
 && popd \
 && git clone --recursive https://github.com/TACC/Lmod.git \
 && pushd Lmod \
 && ./configure --prefix=/usr \
 && make -j 4 \
 && make install \
 && echo "source /usr/lmod/lmod/init/bash" >> /etc/bash.bashrc \
 && echo "source /usr/lmod/lmod/init/bash" >> /etc/profile \
 && popd \
 && rm -rf lua* Lmod

# Copy patch files into /tmp for use when installing spack-stack
COPY cc.patch.aarch64 /tmp
COPY cc.patch.x86_64 /tmp
COPY openmpi.package.py.patch.aarch64 /tmp
COPY openmpi.package.py.patch.x86_64 /tmp

# Clone spack-stack and create and configure the unified env
RUN cd /opt \
 && git clone -b release/1.8.0 --recurse-submodules https://github.com/jcsda/spack-stack.git \
 && pushd spack-stack \
 && . ./setup.sh \
 && pushd spack \
 && mv /tmp/cc.patch.$(uname -m) cc.patch \
 && mv /tmp/openmpi.package.py.patch.$(uname -m) openmpi.package.py.patch \
 && patch -f -p0 < openmpi.package.py.patch \
 && patch -f -p0 < cc.patch \
 && popd \
 && spack stack create env --site linux.default --template unified-dev --name unified-env --compiler gcc \
 && pushd envs/unified-env \
 && spack env activate . \
 && spack mirror add --s3-access-key-id "" --s3-access-key-secret "" s3_spack_stack_buildcache_ro s3://chiltepin-us-east-2/spack-stack/ \
 && export SPACK_SYSTEM_CONFIG_PATH="$PWD/site" \
 && spack external find --scope system \
    --exclude cmake \
    --exclude curl \
    --exclude openssl \
    --exclude openssh \
    --exclude python \
 && spack external find --scope system wget \
 && spack compiler find --scope system \
 && unset SPACK_SYSTEM_CONFIG_PATH \
 && spack config add "packages:all:compiler:[gcc@11.4.0]" \
 && spack config add "packages:all:providers:mpi:[openmpi@4.1.6]" \
 && spack config add "packages:fontconfig:variants:+pic" \
 && spack config add "packages:pixman:variants:+pic" \
 && spack config add "packages:cairo:variants:+pic" \
 && spack config --scope env:/opt/spack-stack/envs/unified-env:common add "packages:openmpi:require:~internal-hwloc +two_level_namespace schedulers=slurm +pmi" \
 && echo "  slurm:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    externals:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    - spec: slurm@23.11.7" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "      prefix: /usr" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    buildable: false" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && if [ "$(uname -m)" == "aarch64" ]; then \
      spack config --scope env:/opt/spack-stack/envs/unified-env:common remove "packages:wgrib2" ; \
      spack config --scope env:/opt/spack-stack/envs/unified-env:common remove "modules:default:lmod:wgrib2" ; \
    fi \
 && sed -i 's/tcl/lmod/g' site/modules.yaml \
 && sed -i 's/tcl/lmod/g' common/modules.yaml \
 && sed -i 's:{^mpi.name}/{^mpi.version}/{compiler.name}/{compiler.version}/{name}:{name}:' common/modules.yaml \
 && sed -i 's:{compiler.name}/{compiler.version}/{name}:{name}:' common/modules.yaml

# Concretize the Spack environment
RUN cd /opt/spack-stack \
 && . ./setup.sh \
 && cd /opt/spack-stack/envs/unified-env \
 && spack env activate . \
 && spack concretize 2>&1 | tee log.concretize

# Install the Spack environment
RUN --mount=type=secret,id=access_key_id --mount=type=secret,id=secret_access_key --mount=type=secret,id=session_token <<EOF
  # Install spack-stack and setup environment
  cd /opt
  pushd spack-stack
  . ./setup.sh
  pushd envs/unified-env
  spack env activate .

  # Add an autopush buildcache mirror if credentials were provided
  if [ -f /run/secrets/access_key_id ]; then
    export AWS_ACCESS_KEY_ID=$(cat /run/secrets/access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(cat /run/secrets/secret_access_key)
    export AWS_SESSION_TOKEN=$(cat /run/secrets/session_token)
    spack mirror add --s3-access-key-id $AWS_ACCESS_KEY_ID --s3-access-key-secret $AWS_SECRET_ACCESS_KEY --s3-access-token $AWS_SESSION_TOKEN --autopush --unsigned s3_spack_stack_buildcache_rw s3://chiltepin-us-east-2/spack-stack/
  fi

  # Install the environment, use autopush buildcache if credentials were provided
  spack install --no-check-signature # 2>&1 | tee log.install
  if [ -f /run/secrets/access_key_id ]; then  
    spack buildcache update-index s3_spack_stack_buildcache_rw
  fi
EOF

# Create the modulefiles and cleanup
RUN cd /opt \
 && pushd spack-stack \
 && . ./setup.sh \
 && pushd envs/unified-env \
 && spack env activate . \
 && source /usr/lmod/lmod/init/bash \
 && spack module lmod refresh -y \
 && spack stack setup-meta-modules \
 && spack gc -y \
 && find /opt/spack-stack/envs/unified-env/install/gcc/11.4.0 -name .spack -type d -print0 | xargs -0 rm -rf "{}" \
 && rm -rf ~/.spack

# Copy installed environment into final images
FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-frontend:latest

COPY --from=builder /usr /usr
COPY --from=builder /etc /etc
COPY --from=builder /opt/spack-stack/envs/unified-env/install /opt/spack-stack/envs/unified-env/install
