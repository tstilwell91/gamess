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

# Copy and extract GAMESS
COPY gamess-2024.2.1.tar.gz /tmp/gamess.tar.gz
RUN mkdir -p /opt/gamess && \
    tar -xzf /tmp/gamess.tar.gz -C /opt/gamess --strip-components=1 && \
    rm /tmp/gamess.tar.gz

# Set up GAMESS
WORKDIR /opt/gamess
RUN sed -i 's|set GMSPATH=.*|set GMSPATH=/opt/gamess|' rungms && \
    chmod +x bin/create-install-info.py && \
    python3 bin/create-install-info.py \
       --target linux64 \
       --path /opt/gamess \
       --build_path /opt/gamess \
       --version 00 \
       --fortran gfortran \
       --fortran_version 11.4 \
       --math openblas \
       --mathlib_path /usr/lib/x86_64-linux-gnu/openblas64-openmp \
       --ddi_comm mpi \
       --mpi_lib impi \
       --mpi_path /usr/local \
       --openmp \
       --rungms

# Build GAMESS
RUN make ddi && make

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
