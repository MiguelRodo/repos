# Use the official Ubuntu image as the base
FROM bioconductor/bioconductor_docker:RELEASE_3_20

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Automatically record build time
RUN mkdir -p /usr/local/etc/container_metadata && \
    date -u '+BUILD_DATE=%Y-%m-%dT%H:%M:%SZ' \
      > /usr/local/etc/container_metadata/build_info.txt

# Copy the `.devcontainer/renv` folder to the container
COPY .devcontainer/renv /usr/local/share/config-r/renv

# Set appropriate permissions
RUN chmod -R 755 /usr/local/share/config-r/renv
