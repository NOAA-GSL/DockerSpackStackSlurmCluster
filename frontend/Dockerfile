FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-frontend:latest AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

SHELL ["/bin/bash", "-c"]

# Install OS packages
RUN apt-get -y update \
 && apt-get -y install --no-install-recommends \
        bc \
        build-essential \
        ca-certificates \
        curl \
        emacs \
        file \
        gcc-13 \
        g++-13 \
        gfortran-13 \
        cpp-13 \
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
        lua5.4 \
        liblua5.4-dev \
        lua-posix \
        lua-filesystem \
        tcl-dev \
        tcsh \
        unzip \
        zstd \
 && rm -rf /var/lib/apt/lists/* \
 && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 100 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-13 \
    --slave /usr/bin/gfortran gfortran /usr/bin/gfortran-13

# Install Lmod
RUN git clone --recursive https://github.com/TACC/Lmod.git \
 && pushd Lmod \
 && ./configure --prefix=/usr \
 && make -j 4 \
 && make install \
 && echo "source /usr/lmod/lmod/init/bash" >> /etc/bash.bashrc \
 && echo "source /usr/lmod/lmod/init/bash" >> /etc/profile \
 && popd \
 && rm -rf Lmod

# Clone spack-stack 2.1.0
RUN cd /opt \
 && git clone -b 2.1.0 --recurse-submodules https://github.com/jcsda/spack-stack.git

# Create and configure the unified env using the container site
RUN cd /opt/spack-stack \
 && source setup.sh \
 && spack stack create env --site container --template unified-dev --name unified-env --compiler gcc \
 && cd envs/unified-env \
 && spack env activate . \
 # Fix system external versions for Ubuntu 26.04 \
 && spack external find --scope "env:/opt/spack-stack/envs/unified-env:/opt/spack-stack/envs/unified-env/site" \
    --exclude cmake \
    --exclude curl \
    --exclude openssl \
    --exclude openssh \
    --exclude python \
 && spack external find --scope "env:/opt/spack-stack/envs/unified-env:/opt/spack-stack/envs/unified-env/site" wget \
 # Add slurm as an external package \
 && echo "  slurm:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    externals:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    - spec: slurm@25.11.5" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "      prefix: /usr" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    buildable: false" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 # Add munge as an external package so spack uses the system munge (same one munged starts at boot) \
 # rather than building its own, which would cause LD_LIBRARY_PATH conflicts with system Slurm tools \
 && MUNGE_VERSION=$(dpkg -l munge 2>/dev/null | awk '/^ii/{print $3}' | cut -d: -f2 | cut -d- -f1 || echo "0.5.16") \
 && echo "  munge:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    externals:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    - spec: munge@${MUNGE_VERSION}" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "      prefix: /usr" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    buildable: false" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 # Configure openmpi to use Slurm scheduler integration (OpenMPI 5 uses PMIx, not +pmi) \
 && spack -e . config add 'packages:openmpi:require:[schedulers=slurm]' \
 # Ensure PMIx includes munge security plugin to avoid psec/munge runtime warnings.
 # Use require (not just variants preference) so concretization cannot silently pick ~munge. \
 && spack -e . config add 'packages:pmix:require:[+munge]' \
 # Configure lmod modules instead of tcl \
 && sed -i 's/tcl/lmod/g' site/modules.yaml \
 # Use unhashed module names like other spack-stack deployments, with Ursa-style suffix rules to avoid naming clashes \
 && printf '%s\n' \
   '      hash_length: 0' \
   '      all:' \
   '        suffixes:' \
   '          +debug: debug' \
   '          build_type=Debug: debug' \
   '      esmf:' \
   '        suffixes:' \
   '          ~openmp: noopenmp' \
   '      ip:' \
   '        suffixes:' \
   '          ~openmp: noopenmp' \
   '      neptune-env:' \
   '        suffixes:' \
   '          ~openmp: noopenmp' \
   '      mapl:' \
   '        suffixes:' \
   '          ^esmf@8.6.1~debug ~openmp snapshot=none: esmf-8.6.1-noopenmp' \
   '          ^esmf@8.6.1+debug ~openmp snapshot=none: esmf-8.6.1-debug-noopenmp' \
   '          ^esmf@8.6.1~debug +openmp snapshot=none: esmf-8.6.1' \
   '          ^esmf@8.6.1+debug +openmp snapshot=none: esmf-8.6.1-debug' \
   '          ^esmf@8.8.0~debug ~openmp snapshot=none: esmf-8.8.0-noopenmp' \
   '          ^esmf@8.8.0+debug ~openmp snapshot=none: esmf-8.8.0-debug-noopenmp' \
   '          ^esmf@8.8.0~debug +openmp snapshot=none: esmf-8.8.0' \
   '          ^esmf@8.8.0+debug +openmp snapshot=none: esmf-8.8.0-debug' \
   '          ^esmf@8.9.1~debug ~openmp snapshot=none: esmf-8.9.1-noopenmp' \
   '          ^esmf@8.9.1+debug ~openmp snapshot=none: esmf-8.9.1-debug-noopenmp' \
   '          ^esmf@8.9.1~debug +openmp snapshot=none: esmf-8.9.1' \
   '          ^esmf@8.9.1+debug +openmp snapshot=none: esmf-8.9.1-debug' \
   '      fms:' \
   '        suffixes:' \
   '          constants=GEOS: geos-constants' \
   '          constants=GFS: gfs-constants' \
   >> site/modules.yaml \
 # Force env module root so final stage can copy a stable path \
 && spack -e . config add 'modules:default:roots:lmod:$env/modules'
 # TODO: Check if wgrib2 removal is still needed for aarch64 with spack-stack 2.1.0 and ubuntu 26.04.
 # This was needed for old spack-stack and ubuntu 22.04, but may be obsolete now.
 # Uncomment below if aarch64 CI build fails with wgrib2 error:
 # && if [ "$(uname -m)" == "aarch64" ]; then \
 #      spack config --scope common remove "packages:wgrib2" ; \
 #      spack config --scope common remove "modules:default:lmod:wgrib2" ; \
 #    fi

# Add the build cache mirror and concretize
RUN cd /opt/spack-stack \
 && source setup.sh \
 && cd envs/unified-env \
 && spack env activate . \
 && spack mirror add --unsigned ghcr_buildcache oci://ghcr.io/noaa-gsl/dockerspackstackslurmcluster/buildcache \
 && spack concretize 2>&1 | tee log.concretize \
 && spack spec openmpi | tee log.openmpi.spec \
 && grep -Eq 'schedulers(:=|=)slurm' log.openmpi.spec \
 && spack spec pmix | tee log.pmix.spec \
 && grep -q '+munge' log.pmix.spec \
 && grep -q 'munge' log.pmix.spec

# Install the Spack environment
RUN --mount=type=secret,id=github_token <<EOF
  cd /opt/spack-stack
  source setup.sh
  cd envs/unified-env
  spack env activate .

  # Add an autopush buildcache mirror if a GitHub token was provided
  if [ -f /run/secrets/github_token ]; then
    export GITHUB_TOKEN=$(cat /run/secrets/github_token)
    spack mirror set --autopush --oci-username x-access-token --oci-password-variable GITHUB_TOKEN ghcr_buildcache
  fi

  # Install the environment
  spack install --no-check-signature 2>&1 | tee log.install

  # Update the build cache index if credentials were provided
  if [ -f /run/secrets/github_token ]; then
    spack buildcache update-index ghcr_buildcache
  fi
EOF

# Create the modulefiles and cleanup
RUN cd /opt/spack-stack \
 && source setup.sh \
 && cd envs/unified-env \
 && source /usr/lmod/lmod/init/bash \
 && spack -e . module lmod refresh -y --delete-tree \
 && spack -e . stack setup-meta-modules \
 && spack gc -y \
 && rm -rf ~/.spack

# Verify module layout before final stage COPY and create a compatibility path if needed
RUN set -euxo pipefail \
 && env_dir=/opt/spack-stack/envs/unified-env \
 && if [ -d "$env_dir/modules" ]; then \
      module_root="$env_dir/modules"; \
    elif [ -d "$env_dir/install/modulefiles" ]; then \
      ln -s "$env_dir/install/modulefiles" "$env_dir/modules"; \
      module_root="$env_dir/modules"; \
    else \
      alt_root=$(find "$env_dir/install" -type d -name modulefiles | head -n 1 || true); \
      if [ -n "$alt_root" ]; then \
        ln -s "$alt_root" "$env_dir/modules"; \
        module_root="$env_dir/modules"; \
      else \
        echo "ERROR: No module directory found under $env_dir"; \
        find "$env_dir" -maxdepth 5 -type d | sort; \
        exit 1; \
      fi; \
    fi \
 && test -d "$module_root/Core" \
 && ls -la "$module_root/Core"

# Copy installed environment into final image
FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-frontend:latest

# Default Slurm MPI plugin so users do not need to pass --mpi=pmix on every srun.
ENV SLURM_MPI_TYPE=pmix

COPY --from=builder /usr /usr
COPY --from=builder /etc /etc
COPY --from=builder /opt/spack-stack/envs/unified-env/install /opt/spack-stack/envs/unified-env/install
COPY --from=builder /opt/spack-stack/envs/unified-env/modules /opt/spack-stack/envs/unified-env/modules
