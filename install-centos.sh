#!/usr/bin/env bash

## Setting variables
hostn=$(cat /etc/hostname)
unchainetname=unchainet

## Checking for passed arguments-------------------------------
if [ ! -n "$1" ]; then
	echo 'Missed argument : resourcebucket'
	exit 1
fi
if [ ! -n "$2" ]; then
	echo 'Missed argument : join token'
	exit 1
fi
if [ ! -n "$3" ]; then
	echo 'Missed argument : api server token'
	exit 1
fi
if [ "$(id -u)" != "0" ]; then
	echo "You need to run this command with sudo"
	exit 1
fi

## Applying unchainet hostname---------------------------------
if [ "${hostn/$unchainetname}" = "$hostn" ]; then
	newhostname=unchainet-$(uuidgen)
	echo "Renaming hostname \"$hostn\" to \"$newhostname\""
	hostname $newhostname
	sed -i "s/$hostn/$newhostname/g" /etc/hosts
	sed -i "s/$hostn/$newhostname/g" /etc/hostname
else
	echo "Hostname has already been updated"
fi

## Installing unchainet dependencies---------------------------
echo "[unchainet-installer] installing docker and kubernetes prerequisites"

yum upgrade
yum install -y docker curl

## Adding the Kubernetes repository to yum---------------------
echo "[unchainet-installer] adding kubernetes repo to yum"

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

yum upgrade

echo "[unchainet-installer] installing kubernetes"
yum install -y kubelet-1.10.5-0 kubeadm-1.10.5-0 kubectl-1.10.5-0

## Adding port 10250 to CSF
echo "[unchainet-installer] enabling ports, disabling swap, starting docker"

if grep 10250 /etc/csf/csf.conf; then
	echo "Port already in csf.conf"
else
	sed -i 's/TCP_IN = "/TCP_IN = "10250,/g' /etc/csf/csf.conf
	csf -r
	echo "Port opened"
fi

sudo swapoff -a
sudo systemctl start docker.service
sudo systemctl daemon-reload
sudo systemctl enable kubelet.service
sudo systemctl daemon-reload


echo "[unchainet-installer] Initializing Kubernetes services and connecting to the cluster"
sudo kubeadm join 147.75.88.183:6443 --token $2 --discovery-token-ca-cert-hash sha256:b79caa062296703d138be28d04c9c7c82c108f325c360477af8ea795d2b28fdb

publicIp=`curl v4.ifconfig.co`
kubernetesNodeId=$(cat /etc/hostname)
resourceBucket=$1
generate_post_data()
{
  cat <<EOF
{
  "resourceBucket": "$resourceBucket",
  "name": "$kubernetesNodeId",
  "kubernetesNodeId": "$kubernetesNodeId",
  "kubernetesIpAddress": "$publicIp"
}
EOF
}

curl -i \
-H "Accept: application/json" \
-H "Content-Type:application/json" \
-H "Authorization: Bearer $3"  \
-X POST --data "$(generate_post_data)" "https://api.unchainet.com/api/computeNodes"
