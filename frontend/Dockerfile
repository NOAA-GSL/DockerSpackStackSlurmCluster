# BASE_IMAGE_TAG is the full tag of the base image pulled from the dockerslurmcluster
# registry (e.g., ubuntu-26.04-slurm-25.11.5). When using docker compose this is
# constructed from UBUNTU_VERSION + SLURM_VERSION in .env; when invoking buildx
# directly it can be set via --build-arg BASE_IMAGE_TAG=...
ARG BASE_IMAGE_TAG=ubuntu-26.04-slurm-25.11.5
FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-frontend:${BASE_IMAGE_TAG} AS builder

# Default to 8 build jobs; override with --build-arg SPACK_BUILD_JOBS=16 for larger runners
ARG SPACK_BUILD_JOBS=8

# UBUNTU_VERSION and SPACK_STACK_VERSION are needed in subsequent RUN commands -- both
# for the per-(ubuntu, spack-stack) buildcache mirror URL (so cross-OS / cross-stack
# cache pollution can't happen) and to drive the spack-stack git clone branch. ARGs
# declared before the first FROM only cover FROM substitution; declaring stage-scoped
# ARGs here plus matching ENVs makes them visible to bash inside the RUN heredocs.
ARG UBUNTU_VERSION=26.04
ENV UBUNTU_VERSION=${UBUNTU_VERSION}
ARG SPACK_STACK_VERSION=2.1.0
ENV SPACK_STACK_VERSION=${SPACK_STACK_VERSION}

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

# Clone spack-stack at the version specified by SPACK_STACK_VERSION.
RUN cd /opt \
 && git clone -b ${SPACK_STACK_VERSION} --recurse-submodules https://github.com/jcsda/spack-stack.git

# Replace the bundled munge recipe with upstream version BEFORE any spack env commands.
# This ensures spack never imports the old recipe. Fetch upstream recipe (has 0.5.18 + CVE
# patches), replace the bundled one, then patch in executables/determine_version for auto-detection.
RUN cd /opt/spack-stack \
 && source setup.sh \
 # Locate the bundled munge recipe. \
 && MUNGE_PY=$(spack python -c "import spack.repo; print(spack.repo.PATH.get_pkg_class('munge').module.__file__)") \
 && [ -n "$MUNGE_PY" ] && [ -f "$MUNGE_PY" ] || { \
        echo "ERROR: spack could not locate munge/package.py"; \
        exit 1; \
    } \
 && echo "Found bundled munge recipe at: $MUNGE_PY" \
 # Fetch and replace with upstream recipe. \
 && curl -fsSL "https://raw.githubusercontent.com/spack/spack-packages/develop/repos/spack_repo/builtin/packages/munge/package.py" \
     -o "$MUNGE_PY" \
 && echo "Replaced with upstream recipe" \
 # Patch in executables + determine_version using Spack idioms (inline Python avoids temp files). \
 && python3 <<PATCH
import re
p = "${MUNGE_PY}"
with open(p) as f:
    src = f.read()

if 'executables' in src and 'determine_version' in src:
    print("Recipe already has executables + determine_version")
else:
    insert = (
        '\\n    executables = [r"^munge\$"]\\n'
        '\\n    @classmethod\\n'
        '    def determine_version(cls, exe):\\n'
        '        try:\\n'
        '            output = Executable(exe)("-V", output=str, error=str)\\n'
        '            match = re.search(r"munge-([0-9.]+)", output)\\n'
        '            return match.group(1) if match else None\\n'
        '        except Exception:\\n'
        '            return None\\n'
    )
    src, n = re.subn(r'(\\n    variant\\(\\n        "localstatedir")', insert + r'\\1', src, count=1)
    if n != 1:
        raise SystemExit("FAIL: could not locate variant for injection")
    with open(p, 'w') as f:
        f.write(src)
    print("Injected executables + determine_version")
PATCH
 # Clear any bytecode cache. \
 && rm -rf "$(dirname "$MUNGE_PY")/__pycache__" \
 && echo "Munge recipe updated successfully"

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
 # Explicit munge detection. The bulk find above scans many packages at once and (as observed) \
 # sometimes fails to pick up newly-patched recipes; an explicit single-package find reliably \
 # uses the patched recipe. Writes to the env scope (spack.yaml), where our `buildable: false` \
 # config_add further below also lands -- both get merged at concretize time. \
 && spack external find munge \
 # Add slurm as an external package \
 && echo "  slurm:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    externals:" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    - spec: slurm@25.11.5" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "      prefix: /usr" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 && echo "    buildable: false" >> /opt/spack-stack/envs/unified-env/site/packages.yaml \
 # Forbid building munge so the concretizer must use the auto-detected system munge. \
 # Auto-detection writes the external entry to packages.yaml but does not set buildable:false. \
 && spack -e . config add 'packages:munge:buildable:false' \
 # Configure openmpi to use Slurm scheduler integration (OpenMPI 5 uses PMIx, not +pmi). \
 # `~internal-pmix` forces openmpi to use the external spack pmix package instead of its \
 # bundled copy. The bundled copy's munge linkage happens at openmpi's autotools configure \
 # time and isn't visible to spack -- so without this constraint, whether munge is actually \
 # wired up depends on opaque base-image detection and could silently change between \
 # concretizer runs. With ~internal-pmix the external pmix is built explicitly, and the \
 # `packages:pmix:require:[+munge]` config_add below guarantees its munge support. \
 && spack -e . config add 'packages:openmpi:require:[schedulers=slurm, ~internal-pmix]' \
 # Ensure PMIx includes munge security plugin to avoid psec/munge runtime warnings.
 # Use require (not just variants preference) so concretization cannot silently pick ~munge. \
 && spack -e . config add 'packages:pmix:require:[+munge]' \
 # Use the spack-stack site default target (x86_64_v3 on x86_64 hosts). \
 # Earlier this block added `target:[x86_64]` for buildcache portability, but spack merged \
 # that with the site default to `[x86_64, x86_64_v3]`, and the concretizer's choice between \
 # them caused manually-declared externals (notably munge) to be rejected on target mismatch. \
 # x86_64_v3 covers Haswell and newer, which is fine for our build/run hardware. \
 # Configure lmod modules instead of tcl \
 && sed -i 's/tcl/lmod/g' site/modules.yaml \
 # Use unhashed module names like other spack-stack deployments, with suffix rules to avoid naming clashes \
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

# Register the per-(ubuntu, spack-stack) buildcache mirror, concretize the env, and
# verify that the four load-bearing configuration choices took effect (munge / slurm
# externals, pmix +munge, openmpi schedulers=slurm). Verification is non-fatal so a
# regression here surfaces as a visible FAIL line in the build log without breaking
# the build outright -- inspect the resulting image with `docker run --entrypoint
# bash` and `spack spec <pkg>` to dig in if anything ever fails here.
RUN <<'EOF'
  set -eo pipefail
  cd /opt/spack-stack
  source setup.sh
  cd envs/unified-env
  spack env activate .
  # Per-(ubuntu, spack-stack) buildcache repo. Splitting by ubuntu prevents cross-OS spec
  # contamination -- spack's reuse:true scoring would otherwise pull e.g. 26.04-built
  # gcc-runtime into a 24.04 concretization, producing a split-brain env with duplicate
  # same-package specs at different OSes that crash module generation. Splitting by
  # spack-stack version isolates recipe-change deltas between releases (different recipes
  # produce different package hashes). Slurm version is NOT in the cache name because
  # slurm is external and doesn't affect spec hashes. GHCR will auto-create the repo on
  # first push (private by default; set visibility from the GHCR UI separately if you
  # want to share read access).
  spack mirror add --unsigned ghcr_buildcache "oci://ghcr.io/noaa-gsl/dockerspackstackslurmcluster/buildcache-ubuntu-${UBUNTU_VERSION}-spack-stack-${SPACK_STACK_VERSION}"

  spack concretize

  # Helpers parse `spack spec --json` and look only at the top-level node, so external
  # deps (e.g. openssl) don't produce false positives in the is_external check.
  is_external() {
    python3 -c '
import json, subprocess, sys
out = subprocess.check_output(["spack", "spec", "--json", sys.argv[1]],
                              text=True, stderr=subprocess.DEVNULL)
n = json.loads(out)["spec"]["nodes"][0]
ext = n.get("external_path")
if not ext:
    e = n.get("external")
    if isinstance(e, dict):
        ext = e.get("path")
sys.exit(0 if ext else 1)
' "$1"
  }
  has_variant() {
    # has_variant <package> <variant>     variant forms: +foo  ~foo  key=val
    python3 -c '
import json, subprocess, sys
out = subprocess.check_output(["spack", "spec", "--json", sys.argv[1]],
                              text=True, stderr=subprocess.DEVNULL)
n = json.loads(out)["spec"]["nodes"][0]
params = n.get("parameters", {})
spec = sys.argv[2]
if spec.startswith("+"):
    sys.exit(0 if params.get(spec[1:]) is True else 1)
if spec.startswith("~"):
    sys.exit(0 if params.get(spec[1:]) is False else 1)
if "=" in spec:
    k, v = spec.split("=", 1)
    val = params.get(k)
    if isinstance(val, list):
        sys.exit(0 if v in val else 1)
    sys.exit(0 if val == v else 1)
sys.exit(2)
' "$1" "$2"
  }

  echo "===== Verification summary ====="
  if is_external munge;   then echo "PASS: munge is external";   else echo "FAIL: munge is NOT external"; fi
  if is_external slurm;   then echo "PASS: slurm is external";   else echo "FAIL: slurm is NOT external"; fi
  if has_variant pmix +munge; then echo "PASS: pmix has +munge variant"; else echo "FAIL: pmix does NOT have +munge variant"; fi
  if has_variant openmpi schedulers=slurm; then echo "PASS: openmpi has schedulers=slurm"; else echo "FAIL: openmpi does NOT have schedulers=slurm"; fi
EOF

# Install the Spack environment
RUN --mount=type=secret,id=github_token <<EOF
  # `set -eo pipefail` ensures spack install failures (or any other step) fail the build
  # loudly. Without these, `spack install | tee log.install` returns tee's exit status
  # (always 0), silently masking partial install failures and producing a "successful"
  # image with missing packages -- which is exactly the trap we fell into before adding
  # these flags. update-index retry below still uses its own non-fatal handling.
  set -eo pipefail
  cd /opt/spack-stack
  source setup.sh
  cd envs/unified-env
  spack env activate .

  # Set parallel build jobs to match CI runner core count
  spack config add config:build_jobs:${SPACK_BUILD_JOBS}

  # Configure buildcache credentials and autopush if a GitHub token was provided
  if [ -s /run/secrets/github_token ]; then
    export GITHUB_TOKEN=$(cat /run/secrets/github_token)
    spack mirror set --autopush --oci-username x-access-token --oci-password-variable GITHUB_TOKEN ghcr_buildcache
  fi

  # Install the environment
  spack install --no-check-signature 2>&1 | tee log.install

  # Update the build cache index if credentials were provided.
  # update-index makes many blob fetches against GHCR to rebuild the index, and we've
  # observed transient SSL / connection-timeout failures on slow or congested links.
  # Per-package artifacts are already published via the autopush mirror setting above,
  # so the buildcache contents are populated regardless of whether the index refreshes.
  # That makes index refresh best-effort: retry a few times, then warn and move on
  # rather than failing the entire build (which would discard hours of install work).
  # A stale index can be refreshed later from any container with GHCR credentials via
  # `spack buildcache update-index ghcr_buildcache`.
  if [ -s /run/secrets/github_token ]; then
    INDEX_OK=0
    for i in 1 2 3 4 5; do
      if spack buildcache update-index ghcr_buildcache; then
        INDEX_OK=1
        echo "buildcache update-index succeeded on attempt \$i"
        break
      fi
      echo "buildcache update-index attempt $i failed, sleeping 30s before retry..."
      sleep 30
    done
    if [ "$INDEX_OK" -ne 1 ]; then
      echo "WARN: buildcache update-index failed after 5 attempts."
      echo "WARN: per-package artifacts ARE in the buildcache via autopush, but the"
      echo "WARN: index is stale until 'spack buildcache update-index ghcr_buildcache'"
      echo "WARN: is run successfully from a container with credentials."
    fi
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

# Copy installed environment into final image
FROM ghcr.io/noaa-gsl/dockerslurmcluster/slurm-frontend:${BASE_IMAGE_TAG}

# Default Slurm MPI plugin so users do not need to pass --mpi=pmix on every srun.
ENV SLURM_MPI_TYPE=pmix

COPY --from=builder /usr /usr
COPY --from=builder /etc /etc
COPY --from=builder /opt/spack-stack/envs/unified-env/install /opt/spack-stack/envs/unified-env/install
COPY --from=builder /opt/spack-stack/envs/unified-env/modules /opt/spack-stack/envs/unified-env/modules
