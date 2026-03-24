FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

# Install systemd and dependencies
RUN apt-get update -qq && \
    apt-get install -y -qq systemd systemd-sysv \
    curl unzip zip screen jq sudo procps iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Remove unnecessary systemd units that cause issues in containers
RUN rm -f /lib/systemd/system/multi-user.target.wants/* \
    /etc/systemd/system/*.wants/* \
    /lib/systemd/system/local-fs.target.wants/* \
    /lib/systemd/system/sockets.target.wants/*udev* \
    /lib/systemd/system/sockets.target.wants/*initctl* \
    /lib/systemd/system/basic.target.wants/* \
    /lib/systemd/system/anaconda.target.wants/*

VOLUME ["/sys/fs/cgroup"]

STOPSIGNAL SIGRTMIN+3

CMD ["/sbin/init"]
