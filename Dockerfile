FROM nvidia/cuda:12.2.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm
ENV USERSCR=/shared/userscr
ENV PATH=/opt/slurm/bin/:$PATH
ENV I_MPI_PMI_LIBRARY=/opt/slurm/lib/libpmi2.so
ENV I_MPI_ROOT=/usr/local
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/openblas64-openmp:$LD_LIBRARY_PATH

# Install required packages
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
    libopenblas64-openmp-dev \
    libhwloc15 libjson-c5 libjwt0 \
 && rm -rf /var/lib/apt/lists/*

# Install Intel MPI runtime via pip
RUN pip3 install jinja2 impi_rt impi_devel

# Workaround for .so versions mismatches
WORKDIR /usr/lib/x86_64-linux-gnu
RUN ln -s libhwloc.so libhwloc.so.5 && \
    ln -s libssl.so.3 libssl.so.10 && \
    ln -s libcrypto.so.3 libcrypto.so.10 && \
    ln -s libjwt.so.0 libjwt.so.2 && \
    ln -s libjson-c.so.5 libjson-c.so.2 && \
    ln -s libreadline.so.8.1 libreadline.so.6 && \
    ln -s libhistory.so.8.1 libhistory.so.6

# Download and install NVIDIA HPC SDK
WORKDIR /tmp
RUN wget https://developer.download.nvidia.com/hpc-sdk/25.3/nvhpc_2025_253_Linux_x86_64_cuda_12.8.tar.gz 
RUN tar -xzf nvhpc_2025_253_Linux_x86_64_cuda_12.8.tar.gz
RUN rm nvhpc_2025_253_Linux_x86_64_cuda_12.8.tar.gz 
RUN NVHPC_SILENT=true \
    NVHPC_INSTALL_DIR=/opt/nvidia/hpc_sdk \
    NVHPC_INSTALL_TYPE=single \
    ./nvhpc_2025_253_Linux_x86_64_cuda_12.8/install_components/install 
RUN rm -rf ./nvhpc_2025_253_Linux_x86_64_cuda_12.8

# Set environment variables for NVIDIA HPC SDK
ENV NVHPC_ROOT=/opt/nvidia/hpc_sdk/Linux_x86_64/25.3
ENV PATH=$NVHPC_ROOT/compilers/bin:$PATH
ENV LIBRARY_PATH=$NVHPC_ROOT/math_libs/lib64:$LIBRARY_PATH
ENV LD_LIBRARY_PATH=$NVHPC_ROOT/math_libs/lib64:$LD_LIBRARY_PATH
ENV CPATH=$NVHPC_ROOT/math_libs/include:$CPATH

# Explicitly compile for selected GPU architectures:
# - sm_70: NVIDIA Volta (e.g., V100)
# - sm_80: NVIDIA Ampere (e.g., A100)
# - sm_89: NVIDIA Ada Lovelace (e.g., L4)
# - sm_90: NVIDIA Hopper (e.g., H100)
ENV NVFORTRAN_CUDAFLAGS="-gpu=ccall,cc70,cc80,cc89,cc90"


# Copy and extract GAMESS
COPY gamess-2024.2.1.tar.gz /tmp/gamess.tar.gz
RUN mkdir -p /opt/gamess 
RUN tar -xzf /tmp/gamess.tar.gz -C /opt/gamess --strip-components=1 
RUN rm /tmp/gamess.tar.gz

# Set up GAMESS
WORKDIR /opt/gamess
RUN sed -i 's|set GMSPATH=.*|set GMSPATH=/opt/gamess|' rungms 

RUN chmod +x bin/create-install-info.py && \
    python3 bin/create-install-info.py \
      --target linux64 \
      --path /opt/gamess \
      --build_path /opt/gamess \
      --version 00 \
      --fortran nvfortran \
      --fortran_version 25.3 \
      --math nvblas \
      --mathlib_path /opt/nvidia/hpc_sdk/Linux_x86_64/2025/math_libs/lib64 \
      --ddi_comm mpi \
      --mpi_lib impi \
      --mpi_path /usr/local \
      --openmp \
      --openmp-offload \
      --cublas \
      --rungms 
RUN sed -i 's|^setenv GMS_LAPACK_LINK_LINE.*|setenv GMS_LAPACK_LINK_LINE "-L/opt/nvidia/hpc_sdk/Linux_x86_64/2025/math_libs/lib64 -lblas_ilp64 -llapack_ilp64 -L/opt/nvidia/hpc_sdk/Linux_x86_64/2025/cuda/lib64 -lcublas -lcublasLt -lcudart -lcuda"|' install.info
RUN ls -l install.info && cat install.info

# Build GAMESS
RUN /bin/csh -c 'source install.info; make ddi && make'

# Patch rungms for flexible Apptainer container name via ENV
RUN sed -i /opt/gamess/rungms \
    -e 's|set MPI_KICKOFF_STYLE=.*|set MPI_KICKOFF_STYLE=slurm|' \
    -e 's|-c \${OMP_NUM_THREADS} \$GMSPATH/gamess.\$VERNO.x|-c ${OMP_NUM_THREADS} $CRUN $GMSPATH/gamess.$VERNO.x|' \
    -e 's|srun --exclusive --export=ALL|srun --mpi=pmi2 --exclusive --export=ALL|' \
    -e "5i if (! \$?GAMESS_CONTAINER) setenv GAMESS_CONTAINER gamess_container" \
    -e "6i set CRUN='apptainer exec -B /shared -B /opt/slurm -B /etc/passwd -B /run/slurm -B /var/spool/slurmd -B /opt/aws/pcs/scheduler --sharens \$GAMESS_CONTAINER'"

# Default behavior
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/opt/gamess/rungms"]

# Interactive working directory
WORKDIR /opt/gamess
