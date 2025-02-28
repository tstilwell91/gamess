# Use an NVIDIA CUDA development base image.
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04

# Prevent interactive prompts during package installation.
ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

# Install system packages, including the 64-bit integer OpenBLAS dev package.
RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    wget \
    tar \
    csh \
    patch \
    cmake \
    doxygen \
    python3 \
    python3-pip \
    libopenblas64-dev \
    && rm -rf /var/lib/apt/lists/*

# Install jinja2 (needed by GAMESS's create-install-info.py).
RUN pip3 install jinja2

# (Optional) Set the library path for OpenBLAS (usually unnecessary on Ubuntu, but can help)
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/openblas64:$LD_LIBRARY_PATH

# Copy the GAMESS source tarball into the container.
COPY gamess-2024.2.1.tar.gz /tmp/gamess.tar.gz

# Extract GAMESS into /opt/gamess.
RUN mkdir -p /opt/gamess && \
    tar -xzvf /tmp/gamess.tar.gz -C /opt/gamess --strip-components=1 && \
    rm /tmp/gamess.tar.gz

# Set the working directory to the GAMESS source.
WORKDIR /opt/gamess

# Update the GMSPATH variable inside rungms to point to /opt/gamess
RUN sed -i 's|set GMSPATH=.*|set GMSPATH=/opt/gamess|' rungms

# Generate the install.info file non-interactively.
# Note: Point --mathlib_path to the OpenBLAS64 location.
RUN chmod +x bin/create-install-info.py && \
    python3 bin/create-install-info.py \
       --target linux64 \
       --path /opt/gamess \
       --build_path /opt/gamess \
       --version 00 \
       --math openblas \
       --mathlib_path /usr/lib/x86_64-linux-gnu/openblas64-pthread \
       --ddi_comm sockets \
       --fortran gfortran \
       --fortran_version 11.4

# Build GAMESS.
RUN make ddi && make -j"$(nproc)"

# Define the container's default behavior.
ENTRYPOINT ["/opt/gamess/rungms-dev"]
