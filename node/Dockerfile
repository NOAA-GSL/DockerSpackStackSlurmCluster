FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-node:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

SHELL ["/bin/bash", "-c"]

RUN <<EOF
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
        tcsh \
        unzip \
        zstd
  rm -rf /var/lib/apt/lists/*

  pip3 install boto3
  
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

EOF
