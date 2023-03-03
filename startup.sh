#!/bin/bash
# this is a very dumb script. but it works
if [[ $(whoami) != 'root' ]]; then echo "not root, exiting"; exit; fi # only really needed for firewall-cmd
OS_ID=$(cat /etc/os-release | grep ^ID | cut -f2 -d "=")
ZONE=$(cat /etc/firewalld/firewalld.conf | grep DefaultZone | cut -d "=" -f2) # could be trusted or public
if [[ $(sysctl net.ipv4.ip_forward -n) != 1 ]]; then sysctl -w net.ipv4.ip_forward=1; fi

function forwardPort() {
    PROTO=$1
    PORT_IN=$2
    PORT_OUT=$3
    if [[ -z $PORT_OUT ]]; then PORT_OUT=$PORT_IN; fi
    IP_OUT=192.168.196.200
    echo "FORWARDING PORT $PORT_IN TO $IP_OUT:$PORT_OUT"

    firewall-cmd --zone=$ZONE --add-port=$PORT_IN/$PROTO
    firewall-cmd --zone=$ZONE --add-forward-port=port=$PORT_IN:proto=$PROTO:toport=$PORT_OUT:toaddr=$IP_OUT
}

function createSwap {
    if [[ ! -f /var/swap ]]; then 
        echo "CREATING SWAP"
        dd if=/dev/zero of=/var/swap bs=4M count=384
        chmod 0600 /var/swap
        mkswap /var/swap
    fi
    echo "ENABLING SWAP"
    swapon /var/swap
}

function installFirewallcmd {
    apt --version && apt install -y firewalld
    dnf --version && dnf install -y firewalld
    zypper --version && zypper install -y firewalld
    systemctl enable --now firewalld
}

function installPodman {
    apt --version && apt install -y podman
    dnf --version && dnf install -y podman
    zypper --version && zypper install -y podman
}

function installGsutil {
    tee -a /etc/zypp/repos.d/google-cloud-sdk.repo << EOM
        [google-cloud-sdk]
        name=Google Cloud SDK
        baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
        enabled=1
        gpgcheck=1
        repo_gpgcheck=1
        gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
               https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
     zypper --gpg-auto-import-keys install -y google-cloud-sdk

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


if [[ $(swapon | wc -l) -eq 0 ]]; then createSwap; fi
apt --version && apt update
firewall-cmd --version || installFirewallcmd
podman --version || installPodman
gsutil --version || installGsutil

setupZerotier

firewall-cmd --zone=$ZONE --add-masquerade
forwardPort tcp 58846
forwardPort tcp 25565
forwardPort tcp 25569
forwardPort tcp 42069
forwardPort udp 19132
forwardPort tcp 8081
forwardPort tcp 8081
forwardPort tcp 18525 22