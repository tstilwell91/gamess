# Use a CUDA 12.8 development base image
FROM nvidia/cuda:12.8.0-devel-ubuntu22.04

# Set environment to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    bash \
    wget \
    tar \
    csh \
    patch \
    cmake \
    doxygen \
    python3 \
    python3-pip \
    libopenblas64-dev \
    liblapack-dev \
    openmpi-bin \
    libopenmpi-dev \
    libomp-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# OpenMP + GPU Offload settings
ENV GMS_OPENMP=true \
    GMS_OPENMP_OFFLOAD=true

# GAMESS requires a non-64 symlink
RUN ln -s /usr/lib/x86_64-linux-gnu/openblas64-pthread/libopenblas64.a \
          /usr/lib/x86_64-linux-gnu/openblas64-pthread/libopenblas.a

# Install Python dependencies
RUN pip3 install jinja2

# Set library path
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/openblas64:/usr/lib/x86_64-linux-gnu/openblas64-pthread:$LD_LIBRARY_PATH

# Set version for NVIDIA HPC SDK
ENV NVHPC_VERSION=25.3
ENV NVHPC_HOME=/opt/nvidia/hpc_sdk/Linux_x86_64/${NVHPC_VERSION}

# Install NVIDIA HPC SDK with nvfortran for CUDA 12.8
RUN wget https://developer.download.nvidia.com/hpc-sdk/25.3/nvhpc_2024_253_Linux_x86_64_cuda_12.8.tar.gz && \
    tar -xzf nvhpc_2024_253_Linux_x86_64_cuda_12.8.tar.gz -C /opt && \
    rm nvhpc_2024_253_Linux_x86_64_cuda_12.8.tar.gz && \
    /opt/nvidia/hpc_sdk/Linux_x86_64/${NVHPC_VERSION}/install -silent

# Update PATH and environment
ENV PATH=${NVHPC_HOME}/bin:$PATH
ENV MANPATH=${NVHPC_HOME}/man:$MANPATH
ENV LD_LIBRARY_PATH=${NVHPC_HOME}/lib:$LD_LIBRARY_PATH

# Copy GAMESS tarball into container
COPY gamess-2024.2.1.tar.gz /tmp/gamess.tar.gz

# Extract GAMESS into /opt/gamess
RUN mkdir -p /opt/gamess && \
    tar -xzvf /tmp/gamess.tar.gz -C /opt/gamess --strip-components=1 && \
    rm /tmp/gamess.tar.gz

# Set working directory
WORKDIR /opt/gamess

# Patch rungms to set GMSPATH
RUN sed -i 's|set GMSPATH=.*|set GMSPATH=/opt/gamess|' rungms

# Generate install.info for nvfortran + GPU offload
RUN chmod +x bin/create-install-info.py && \
    python3 bin/create-install-info.py \
       --target linux64 \
       --path /opt/gamess \
       --build_path /opt/gamess \
       --version 00 \
       --fortran nvfortran \
       --fortran_version 25.3 \
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

# Default command
ENTRYPOINT ["/opt/gamess/rungms-dev"]
