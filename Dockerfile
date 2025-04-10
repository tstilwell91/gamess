FROM nvidia/cuda:12.8.0-devel-rockylinux9

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

# Install system dependencies and development tools
RUN dnf -y update && dnf -y install \
    make \
    cmake \
    gcc \
    gcc-c++ \
    gfortran \
    openmpi \
    openmpi-devel \
    boost-devel \
    eigen3-devel \
    zlib-devel \
    python3 \
    python3-pip \
    curl \
    git \
    which \
    wget \
    tar \
    && dnf clean all

# Set up MPI environment
ENV PATH=/usr/lib64/openmpi/bin:$PATH
ENV LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH

# Install Python dependencies
RUN pip3 install jinja2

# Install Miniconda and MKL libraries
RUN curl -sLo ~/miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    /opt/conda/bin/conda install -y -c intel mkl mkl-include && \
    /opt/conda/bin/conda clean -afy

ENV PATH="/opt/conda/bin:$PATH"
ENV MKLROOT="/opt/conda"

# Install HDF5 from source (parallel enabled)
RUN mkdir -p /opt/src && cd /opt/src && \
    curl -LO https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.12/hdf5-1.12.1/src/hdf5-1.12.1.tar.bz2 && \
    tar -xjf hdf5-1.12.1.tar.bz2 && \
    cd hdf5-1.12.1 && \
    ./configure --enable-parallel --enable-fortran --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    cd .. && rm -rf hdf5-1.12.1*

ENV HDF5_ROOT=/usr/local

# Install Global Arrays (GA) from GitHub (5.8+)
RUN cd /opt/src && \
    git clone https://github.com/GlobalArrays/ga.git && \
    cd ga && \
    git checkout v5.8.1 && \
    mkdir build && cd build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=/opt/ga \
        -DBUILD_SHARED_LIBS=ON \
        -DGA_MPI=ON \
        -DGA_BLAS_LIBRARIES="-L${MKLROOT}/lib -lmkl_gf_ilp64 -lmkl_gnu_thread -lmkl_core -lgomp -lpthread -lm -ldl" \
        -DGA_SCALAPACK_LIBRARIES="-L${MKLROOT}/lib -lmkl_scalapack_ilp64 -lmkl_blacs_openmpi_ilp64" && \
    make -j$(nproc) && make install

ENV GA_PATH=/opt/ga
ENV LD_LIBRARY_PATH=$GA_PATH/lib:$LD_LIBRARY_PATH

# Copy GAMESS source tarball into image (assumed to be added later)
COPY gamess-2024.2.1.tar.gz /tmp/gamess.tar.gz

# Extract GAMESS
RUN mkdir -p /opt/gamess && \
    tar -xzf /tmp/gamess.tar.gz -C /opt/gamess --strip-components=1 && \
    rm /tmp/gamess.tar.gz

# Set working directory
WORKDIR /opt/gamess

# Patch path inside rungms
RUN sed -i 's|set GMSPATH=.*|set GMSPATH=/opt/gamess|' rungms

# Generate install.info non-interactively
RUN python3 bin/create-install-info.py \
    --target linux64 \
    --path /opt/gamess \
    --build_path /opt/gamess \
    --version 00 \
    --fortran gfortran \
    --fortran_version 12.2 \
    --math openblas \
    --mathlib_path /opt/conda/lib \
    --mathlib_include_path /opt/conda/include \
    --mpi \
    --mpi_path /usr/lib64/openmpi \
    --mpi_lib openmpi \
    --sysv \
    --openmp \
    --libcchem \
    --libcchem_gpu_support \
    --cuda_path=/usr/local/cuda \
    --ga_path=/opt/ga \
    --boost_path=/usr/include \
    --hdf5_path=/usr/local \
    --eigen_path=/usr/include/eigen3 \
    --rungms

# Compile GAMESS
RUN make ddi && ./compall && make && mv gamess.00.x bin && make clean

# Final environment setup
ENV PATH="/opt/gamess:$PATH"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:/opt/ga/lib:/usr/local/lib:$LD_LIBRARY_PATH"

# Set default command
ENTRYPOINT ["/opt/gamess/rungms-dev"]
