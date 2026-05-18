FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-node:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

SHELL ["/bin/bash", "-c"]

RUN <<EOF
  set -e

  # Install OS packages
  apt-get -y update
  apt-get -y install --no-install-recommends \
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
        subversion \
        lua5.4 \
        liblua5.4-dev \
        lua-posix \
        lua-filesystem \
        tcl-dev \
        tcsh \
        unzip \
        zstd
  rm -rf /var/lib/apt/lists/*

  # Install Lmod
  git clone --recursive https://github.com/TACC/Lmod.git
  pushd Lmod
  ./configure --prefix=/usr
  make -j 4
  make install
  echo "source /usr/lmod/lmod/init/bash" >> /etc/bash.bashrc
  popd
  
  # Cleanup
  rm -rf Lmod

EOF
