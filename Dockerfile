FROM debian:buster-slim

VOLUME /var/local

WORKDIR /rpi

RUN apt-get update && \
    apt-get install -y debootstrap kpartx qemu-user-static xz-utils sharutils wget curl unzip git dosfstools parted && \
    apt-get clean

COPY scripts/build-k3s-cluster-image.sh .

CMD ["bash", "build-k3s-cluster-image.sh"]
