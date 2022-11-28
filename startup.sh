#!/bin/bash
if [[ $(whoami) != 'root' ]]; then echo "not root, exiting"; exit; fi # only really needed for firewall-cmd

if [[ $(swapon | wc -l) -eq 0 ]]; then
    if [[ ! -f /var/swap ]]; then 
        echo "CREATING SWAP"
        dd if=/dev/zero of=/var/swap bs=4M count=512
        chmod 0600 /var/swap
        mkswap /var/swap
    fi
    echo "ENABLING SWAP"
    swapon /var/swap
fi

#apt update
firewall-cmd --version || apt install -y firewalld 
podman --version || apt install -y podman

## ZEROTIER
ZT_ID="$(gsutil cat gs://drath-private/vps_zerotierid.env)"
export ZEROTIER_IDENTITY_PUBLIC=$(echo "$ZT_ID" | grep ZEROTIER_IDENTITY_PUBLIC | cut -d "=" -f2)
export ZEROTIER_IDENTITY_SECRET=$(echo "$ZT_ID" | grep ZEROTIER_IDENTITY_SECRET | cut -d "=" -f2)
modprobe tun
podman run --name zerotier \
    --no-healthcheck \
    --rm -d \
    --cap-add NET_ADMIN \
    --net host \
    --device /dev/net/tun \
    -e ZEROTIER_IDENTITY_PUBLIC \
    -e ZEROTIER_IDENTITY_SECRET \
    docker.io/zerotier/zerotier:latest \
$(echo "$ZT_ID" | grep NETWORKS | cut -d "=" -f2 | tr -d '"')
#rmmod tun

## PORT FORWARDING
ZONE=$(cat /etc/firewalld/firewalld.conf | grep DefaultZone | cut -d "=" -f2) # could be trusted or public
function forwardPort() {
    PROTO=$1
    PORT_IN=$2
    PORT_OUT=$3
    if [[ -z $PORT_OUT ]]; then PORT_OUT=$PORT_IN; fi
    IP_OUT=192.168.196.200
    echo "FORWARDING PORT $PORT_IN TO $IP_OUT:$PORT_OUT"

    firewall-cmd --zone=$ZONE --add-port=$PORT_IN/$PROTO
    firewall-cmd --zone=$ZONE --add-masquerade
    firewall-cmd --zone=$ZONE --add-forward-port=port=$PORT_IN:proto=$PROTO:toport=$PORT_OUT:toaddr=$IP_OUT
}

sysctl -w net.ipv4.ip_forward=1
forwardPort tcp 25565
forwardPort tcp 25569
forwardPort udp 19132
forwardPort tcp 8081
