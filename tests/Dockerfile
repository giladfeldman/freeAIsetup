# Test image: a clean Ubuntu with a normal (non-root) student account that may use sudo,
# like a student laptop. Only the bare minimum is preinstalled; the setup script does the rest.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates sudo python3 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash "jürgen" && echo "jürgen ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/student
USER jürgen
WORKDIR /home/jürgen
