#!/bin/bash
# this is a very dumb script. but it works
if [[ $(whoami) != 'root' ]]; then echo "not root, exiting"; exit; fi
if [[ $(sysctl net.ipv4.ip_forward -n) != 1 ]]; then sysctl -w net.ipv4.ip_forward=1; fi

function prepForwarding() {
	nft add table ip nat
	nft -- add chain ip nat prerouting { type nat hook prerouting priority -100 \; }
	nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
    for ip in $@; do 
        nft add rule ip nat postrouting ip daddr $ip masquerade
        echo "SET UP MASQUERADING FOR $ip"
    done
}

function forwardPort() {
    echo "FORWARDING PORT $2/$1 TO $3"
	nft add rule ip nat prerouting $1 dport $2 dnat to $3
}

function setupZerotier {
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
}


# podman ps -a | grep zerotier || setupZerotier
nft --version || apt update || apt install nftables -y

SERWER=ts-server

prepForwarding $SERWER
forwardPort tcp 58846 $SERWER   # deluge
forwardPort tcp 25565 $SERWER   # minecraft #1
forwardPort tcp 25566 $SERWER   # minecraft #1
forwardPort tcp 25569 $SERWER   # minecraft #2
forwardPort tcp 42069 $SERWER   # minecraft #3
forwardPort udp 19132 $SERWER   # minecraft bedrock
forwardPort tcp 18525 $SERWER:22 # ssh