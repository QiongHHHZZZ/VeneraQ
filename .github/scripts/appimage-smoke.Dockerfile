FROM ubuntu:22.04
# Deliberately no GTK or WebKit packages. Only the display/driver host interface.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    xvfb xdotool dbus-x11 libgl1-mesa-dri libegl1 libgl1 ca-certificates fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 smoke
RUN apt-get -o Acquire::Retries=3 update && apt-get -o Acquire::Retries=3 install -y --no-install-recommends libgles2 \
    && rm -rf /var/lib/apt/lists/*
USER smoke
ENV HOME=/home/smoke
WORKDIR /home/smoke
