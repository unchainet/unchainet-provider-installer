#!/usr/bin/env bash

hostn=$(cat /etc/hostname)
unchainetname=unchainet

if [ ! -n "$1" ] 
then
    echo 'Missed argument : resourcebucket'
    exit 1
fi
if [ ! -n "$2" ] 
then
    echo 'Missed argument : join token'
    exit 1
fi
if [ ! -n "$3" ]
then
    echo 'Missed argument : api server token'
    exit 1
fi
if [ "$(id -u)" != "0" ]; then
	echo "You need to run this command with sudo"
	exit 1
fi

if [ "${hostn/$unchainetname}" = "$hostn" ] ; then
  newhostname=unchainet-$(uuidgen)
  echo "renaming hostname from $hostn to $newhostname"
  sudo hostname $newhostname
  sudo sed -i "s/$hostn/$newhostname/g" /etc/hosts
  sudo sed -i "s/$hostn/$newhostname/g" /etc/hostname
else
  echo ""
fi

echo "[unchainet-installer] installing docker and kubernetes prerequisites"
sudo apt-get update

sudo apt-get install -y docker.io

sudo apt-get install -y apt-transport-https curl

echo "[unchainet-installer] adding kubernetes repo to apt-get"

sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

sudo apt-get update

echo "[unchainet-installer] installing kubernetes"
sudo apt-get install -y kubelet kubeadm kubectl

echo "[unchainet-installer] enabling ports, disabling swap, starting docker"
sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT
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