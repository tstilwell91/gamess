# Use an NVIDIA CUDA base image with development tools.
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

# Install essential packages.
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    curl \
    tar \
    csh \
    cmake \
    doxygen \
    python3 \
    python3-pip \
    gfortran \
    libopenblas64-dev \
    liblapack-dev \
    openmpi-bin \
    libopenmpi-dev \
    libomp-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set up environment variables
ENV NVHPC_VERSION=24.1
ENV NVHPC_ROOT=/opt/nvidia/hpc_sdk
ENV PATH=${NVHPC_ROOT}/Linux_x86_64/${NVHPC_VERSION}/compilers/bin:${PATH}
ENV MANPATH=${NVHPC_ROOT}/Linux_x86_64/${NVHPC_VERSION}/compilers/man:${MANPATH}
ENV LD_LIBRARY_PATH=${NVHPC_ROOT}/Linux_x86_64/${NVHPC_VERSION}/compilers/lib:${LD_LIBRARY_PATH}
ENV LM_LICENSE_FILE=${NVHPC_ROOT}/licenses/license.dat

# Download and install NVIDIA HPC SDK
RUN wget https://developer.download.nvidia.com/hpc-sdk/${NVHPC_VERSION}/nvhpc_${NVHPC_VERSION}_Linux_x86_64_cuda_12.2.tar.gz && \
    tar -xzf nvhpc_${NVHPC_VERSION}_Linux_x86_64_cuda_12.2.tar.gz -C /opt && \
    rm nvhpc_${NVHPC_VERSION}_Linux_x86_64_cuda_12.2.tar.gz && \
    /opt/nvidia/hpc_sdk/Linux_x86_64/${NVHPC_VERSION}/install

# Symlink OpenBLAS to expected name
RUN ln -s /usr/lib/x86_64-linux-gnu/openblas64-pthread/libopenblas64.a \
          /usr/lib/x86_64-linux-gnu/openblas64-pthread/libopenblas.a

# Install Python packages
RUN pip3 install jinja2

# Set OpenMP options
ENV GMS_OPENMP=true \
    GMS_OPENMP_OFFLOAD=true

# Set OpenBLAS library path
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/openblas64:/usr/lib/x86_64-linux-gnu/openblas64-pthread:$LD_LIBRARY_PATH

# Copy GAMESS source tarball into container
COPY gamess-2024.2.1.tar.gz /tmp/gamess.tar.gz

# Extract GAMESS into /opt/gamess
RUN mkdir -p /opt/gamess && \
    tar -xzvf /tmp/gamess.tar.gz -C /opt/gamess --strip-components=1 && \
    rm /tmp/gamess.tar.gz

WORKDIR /opt/gamess

# Fix GMSPATH
RUN sed -i 's|set GMSPATH=.*|set GMSPATH=/opt/gamess|' rungms

# Generate install.info for nvfortran
RUN chmod +x bin/create-install-info.py && \
    python3 bin/create-install-info.py \
       --target linux64 \
       --path /opt/gamess \
       --build_path /opt/gamess \
       --version 00 \
       --fortran nvfortran \
       --fortran_version 24.1 \
       --math openblas \
       --mathlib_path /usr/lib/x86_64-linux-gnu/openblas64-pthread \
       --ddi_comm mpi \
       --mpi_lib openmpi \
       --mpi_path /usr/lib/x86_64-linux-gnu/openmpi \
       --openmp \
       --openmp-offload \
       --cublas

# Build GAMESS
RUN make ddi && make -j"$(nproc)"

# Set default entrypoint
ENTRYPOINT ["/opt/gamess/rungms-dev"]
