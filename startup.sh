#!/bin/bash
# startup script made for fedora-based distros (rhel, centos, rocky, alma)
if [[ $(whoami) != 'root' ]]; then echo "not root, exiting"; exit; fi # only really needed for firewall-cmd

if [[ $(swapon | wc -l) -eq 0 ]]; then
	if [[ ! -f /tmp/swap ]]; then 
		echo "CREATING SWAP"
		dd if=/dev/zero of=/tmp/swap bs=4M count=512
		chmod 0600 /tmp/swap
		mkswap /tmp/swap
	fi
	echo "ENABLING SWAP"
	swapon /tmp/swap
fi	

firewall-cmd --version || dnf install -y firewalld
podman --version || dnf install -y podman

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
# if [[ $(whoami) != 'root' ]]; then echo "not root, exiting"; exit; fi
function forwardPort() {
        PORT_IN=$1
        IP_OUT=192.168.196.200
        PORT_OUT=$2
        PROTO=$3
        ZONE=trusted
        echo "FORWARDING PORT $PORT_IN TO $IP_OUT:$PORT_OUT"

        firewall-cmd --zone=$ZONE --add-port=$PORT_IN/$PROTO
	firewall-cmd --zone=$ZONE --add-masquerade
	firewall-cmd --zone=$ZONE --add-forward-port=port=$PORT_IN:proto=$PROTO:toport=$PORT_OUT:toaddr=$IP_OUT
}
sysctl -w net.ipv4.ip_forward=1
forwardPort 25565 25565 tcp
forwardPort 25569 25569 tcp
forwardPort 19132 19132 udp
forwardPort 8081 8081 tcp
