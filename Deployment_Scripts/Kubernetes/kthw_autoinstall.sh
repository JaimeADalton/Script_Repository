#!/usr/bin/env bash
# kthw_autoinstall.sh — Automatiza "Kubernetes The Hard Way" en Debian 12
# Requisitos: Internet, bash, root en el jumpbox.
# Crea y configura: 1 server (control plane) + N workers. No crea VMs.
set -euo pipefail

############################################
# 0) Parámetros y comprobaciones locales
############################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "Falta $1. Instalando..."; apt-get update -y && apt-get install -y "$1"; }; }

[[ $EUID -eq 0 ]] || { echo "Ejecuta como root."; exit 1; }
need curl; need wget; need openssl; need git; need sshpass; need jq; need tar; need iproute2; need gawk; need sed

# Versiones fijadas y probadas
K8S_VER="v1.32.3"
ETCD_VER="v3.5.15"
CONTAINERD_VER="1.7.22"
CNI_VER="v1.5.1"
CRICTL_VER="v1.32.0"
RUNC_VER="v1.1.13"

ARCH_DEB="$(dpkg --print-architecture)"    # amd64 | arm64
case "$ARCH_DEB" in
  amd64) ARCH_GO="amd64";;
  arm64) ARCH_GO="arm64";;
  *) echo "Arquitectura no soportada: $ARCH_DEB"; exit 1;;
esac

WORKDIR="/root/kubernetes-the-hard-way"
mkdir -p "$WORKDIR"/{downloads,configs,units}
cd "$WORKDIR"

############################################
# 1) Encuesta mínima al operador
############################################
echo "=== Parámetros del despliegue ==="
read -rp "Dominio base (ej: kubernetes.local): " BASEDOM
[[ -n "${BASEDOM}" ]]
SERVER_HOST="server"
SERVER_FQDN="${SERVER_HOST}.${BASEDOM}"

read -rp "IP del server (${SERVER_FQDN}): " SERVER_IP
[[ -n "${SERVER_IP}" ]]

read -rp "Número de workers: " WORKER_COUNT
[[ "${WORKER_COUNT}" =~ ^[0-9]+$ ]] || { echo "Valor inválido"; exit 1; }
(( WORKER_COUNT >= 1 )) || { echo "Se requiere al menos 1 worker"; exit 1; }

# Credenciales SSH comunes para todos los hosts remotos
read -rp "Usuario SSH remoto (se recomienda root): " SSH_USER
read -srp "Password SSH para ${SSH_USER}: " SSH_PASS; echo

# Asignación automática de subredes 10.200.X.0/24 por nodo
declare -a W_NAMES W_FQDNS W_IPS W_PODS
for i in $(seq 0 $((WORKER_COUNT-1))); do
  DEF_NAME="node-${i}"
  read -rp "Hostname del worker #$i [${DEF_NAME}]: " WN; WN="${WN:-$DEF_NAME}"
  read -rp "IP de ${WN}: " WIP
  W_NAMES+=("${WN}")
  W_FQDNS+=("${WN}.${BASEDOM}")
  W_IPS+=("${WIP}")
  W_PODS+=("10.200.${i}.0/24")
done

############################################
# 2) Prepara SSH sin contraseña hacia remotos
############################################
mkdir -p /root/.ssh
if [[ ! -f /root/.ssh/id_rsa ]]; then
  ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa
fi
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
push_key(){
  local host_ip="$1"
  sshpass -p "$SSH_PASS" ssh $SSH_OPTS "${SSH_USER}@${host_ip}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
  sshpass -p "$SSH_PASS" ssh $SSH_OPTS "${SSH_USER}@${host_ip}" "grep -q \"$(cat /root/.ssh/id_rsa.pub)\" ~/.ssh/authorized_keys || echo \"$(cat /root/.ssh/id_rsa.pub)\" >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"
}
run(){ ssh $SSH_OPTS "${SSH_USER}@${1}" "sudo bash -lc '$2'"; }
scp_to(){ scp $SSH_OPTS "$3" "${SSH_USER}@${1}:$2"; }

echo "Distribuyendo clave pública..."
push_key "${SERVER_IP}"
for ip in "${W_IPS[@]}"; do push_key "$ip"; done

############################################
# 3) /etc/hosts en todas las máquinas
############################################
echo "Generando hosts..."
HOSTS_FILE="# Kubernetes The Hard Way Cluster
${SERVER_IP} ${SERVER_FQDN} ${SERVER_HOST}"
for idx in "${!W_NAMES[@]}"; do
  HOSTS_FILE="${HOSTS_FILE}
${W_IPS[$idx]} ${W_FQDNS[$idx]} ${W_NAMES[$idx]}"
done

# Jumpbox
if ! grep -q '# Kubernetes The Hard Way Cluster' /etc/hosts; then
  printf "%s\n" "$HOSTS_FILE" >> /etc/hosts
fi

# Server y workers
echo "Propagando /etc/hosts..."
tmp_hosts="/tmp/hosts.kthw.$$"
printf "%s\n" "$HOSTS_FILE" > "$tmp_hosts"
scp_to "${SERVER_IP}" "~/hosts.kthw" "$tmp_hosts"
run "${SERVER_IP}" "cat ~/hosts.kthw >> /etc/hosts"

for ip in "${W_IPS[@]}"; do
  scp_to "${ip}" "~/hosts.kthw" "$tmp_hosts"
  run "${ip}" "cat ~/hosts.kthw >> /etc/hosts"
done
rm -f "$tmp_hosts"

############################################
# 4) Hostname en server y workers
############################################
run "${SERVER_IP}" "hostnamectl set-hostname ${SERVER_HOST} && sed -i 's/^127.0.1.1.*/127.0.1.1\t${SERVER_FQDN} ${SERVER_HOST}/' /etc/hosts && systemctl restart systemd-hostnamed"
for idx in "${!W_NAMES[@]}"; do
  run "${W_IPS[$idx]}" "hostnamectl set-hostname ${W_NAMES[$idx]} && sed -i 's/^127.0.1.1.*/127.0.1.1\t${W_FQDNS[$idx]} ${W_NAMES[$idx]}/' /etc/hosts && systemctl restart systemd-hostnamed"
done

############################################
# 5) Descarga de binarios en jumpbox
############################################
echo "Descargando binarios..."
cd "$WORKDIR/downloads"

# kubectl y binarios k8s control/worker
curl -fsSLO "https://storage.googleapis.com/kubernetes-release/release/${K8S_VER}/bin/linux/${ARCH_GO}/kubectl"
curl -fsSLO "https://storage.googleapis.com/kubernetes-release/release/${K8S_VER}/bin/linux/${ARCH_GO}/kube-apiserver"
curl -fsSLO "https://storage.googleapis.com/kubernetes-release/release/${K8S_VER}/bin/linux/${ARCH_GO}/kube-controller-manager"
curl -fsSLO "https://storage.googleapis.com/kubernetes-release/release/${K8S_VER}/bin/linux/${ARCH_GO}/kube-scheduler"
curl -fsSLO "https://storage.googleapis.com/kubernetes-release/release/${K8S_VER}/bin/linux/${ARCH_GO}/kubelet"
curl -fsSLO "https://storage.googleapis.com/kubernetes-release/release/${K8S_VER}/bin/linux/${ARCH_GO}/kube-proxy"

# etcd
curl -fsSLO "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-${ARCH_GO}.tar.gz"

# containerd + runc + cni + crictl
curl -fsSLO "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VER}/containerd-${CONTAINERD_VER}-linux-${ARCH_GO}.tar.gz"
curl -fsSLO "https://github.com/opencontainers/runc/releases/download/${RUNC_VER}/runc.${ARCH_GO}"
curl -fsSLO "https://github.com/containernetworking/plugins/releases/download/${CNI_VER}/cni-plugins-linux-${ARCH_GO}-${CNI_VER}.tgz"
curl -fsSLO "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VER}/crictl-${CRICTL_VER}-linux-${ARCH_GO}.tar.gz"

chmod +x kubectl kube-* runc.${ARCH_GO}

mkdir -p ../{client,controller,worker,cni-plugins}
mv kubectl ../client/
mv kube-apiserver kube-controller-manager kube-scheduler ../controller/
mv kubelet kube-proxy runc.${ARCH_GO} ../worker/
mv cni-plugins-linux-${ARCH_GO}-${CNI_VER}.tgz ../
mv containerd-${CONTAINERD_VER}-linux-${ARCH_GO}.tar.gz ../
mv etcd-${ETCD_VER}-linux-${ARCH_GO}.tar.gz ../
mv crictl-${CRICTL_VER}-linux-${ARCH_GO}.tar.gz ../

cd "$WORKDIR"
# Extraer artefactos
tar -xzf downloads/etcd-${ETCD_VER}-linux-${ARCH_GO}.tar.gz -C downloads/ --strip-components=1 etcd-${ETCD_VER}-linux-${ARCH_GO}/etcdctl etcd-${ETCD_VER}-linux-${ARCH_GO}/etcd
mv downloads/etcdctl downloads/etcd downloads/controller/
tar -xzf downloads/containerd-${CONTAINERD_VER}-linux-${ARCH_GO}.tar.gz -C downloads/
tar -xzf downloads/crictl-${CRICTL_VER}-linux-${ARCH_GO}.tar.gz -C downloads/worker/
tar -xzf downloads/cni-plugins-linux-${ARCH_GO}-${CNI_VER}.tgz -C downloads/cni-plugins/

############################################
# 6) Plantillas de configuración y units
############################################
# ca.conf con SANs correctos
cat > configs/ca.conf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no

[dn]
CN = kubernetes

[v3_ca]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign

[ v3_ext_client ]
basicConstraints = CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
subjectAltName = @alt_names_client

[ v3_ext_server ]
basicConstraints = CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names_server

[ alt_names_server ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = server
DNS.6 = server.__BASEDOM__
IP.1 = 10.32.0.1
IP.2 = 127.0.0.1
IP.3 = __SERVER_IP__

[ alt_names_client ]
DNS.1 = kubernetes-client

# Per-entity sections
[admin]
prompt = no
distinguished_name = dn_admin
req_extensions = v3_ext_client

[dn_admin]
CN = admin
O = system:masters
OU = kthw

[kube-controller-manager]
prompt = no
distinguished_name = dn_kcm
req_extensions = v3_ext_client

[dn_kcm]
CN = system:kube-controller-manager
O = system:kube-controller-manager
OU = kthw

[kube-scheduler]
prompt = no
distinguished_name = dn_sched
req_extensions = v3_ext_client

[dn_sched]
CN = system:kube-scheduler
O = system:kube-scheduler
OU = kthw

[kube-proxy]
prompt = no
distinguished_name = dn_kp
req_extensions = v3_ext_client

[dn_kp]
CN = system:kube-proxy
O = system:node-proxier
OU = kthw

[service-accounts]
prompt = no
distinguished_name = dn_sa
req_extensions = v3_ext_client

[dn_sa]
CN = service-accounts
O = kubernetes
OU = kthw

[kube-api-server]
prompt = no
distinguished_name = dn_apiserver
req_extensions = v3_ext_server

[dn_apiserver]
CN = kube-apiserver
O = kubernetes
OU = kthw

# Nodos (plantilla). Se usará con -section node-<name> generada dinámicamente.
EOF

# Kube-scheduler config
cat > configs/kube-scheduler.yaml <<'EOF'
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF

# Kube-proxy config (clusterCIDR fijo 10.200.0.0/16 para este tutorial)
cat > configs/kube-proxy-config.yaml <<'EOF'
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
kubeconfig: "/var/lib/kube-proxy/kubeconfig"
EOF

# CNI bridge y loopback
cat > configs/10-bridge.conf.tpl <<'EOF'
{
  "cniVersion": "0.4.0",
  "name": "bridge",
  "type": "bridge",
  "bridge": "cni0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "ranges": [[{ "subnet": "SUBNET" }]],
    "routes": [{ "dst": "0.0.0.0/0" }]
  }
}
EOF

cat > configs/99-loopback.conf <<'EOF'
{
  "cniVersion": "0.4.0",
  "type": "loopback"
}
EOF

# Kubelet config plantilla
cat > configs/kubelet-config.yaml.tpl <<'EOF'
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubelet/ca.crt"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
runtimeRequestTimeout: "15m"
cgroupDriver: "systemd"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
EOF

# containerd config
cat > configs/containerd-config.toml <<'EOF'
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.10"
  [plugins."io.containerd.grpc.v1.cri".containerd]
    default_runtime_name = "runc"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      runtime_type = "io.containerd.runc.v2"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true
EOF

# Units systemd
cat > units/etcd.service <<'EOF'
[Unit]
Description=etcd
Documentation=https://etcd.io
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \
  --name controller \
  --data-dir=/var/lib/etcd \
  --listen-peer-urls=http://127.0.0.1:2380 \
  --listen-client-urls=http://127.0.0.1:2379 \
  --advertise-client-urls=http://127.0.0.1:2379 \
  --initial-advertise-peer-urls=http://127.0.0.1:2380 \
  --initial-cluster=controller=http://127.0.0.1:2380
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# kube-apiserver.service (usa variables en expansión al instalar en server)
cat > units/kube-apiserver.service.tpl <<'EOF'
[Unit]
Description=Kubernetes API Server
After=network.target etcd.service
Wants=etcd.service

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --advertise-address=__SERVER_IP__ \
  --allow-privileged=true \
  --authorization-mode=Node,RBAC \
  --client-ca-file=/var/lib/kubernetes/ca.crt \
  --enable-admission-plugins=NodeRestriction,ServiceAccount \
  --etcd-servers=http://127.0.0.1:2379 \
  --event-ttl=1h \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.crt \
  --kubelet-client-certificate=/var/lib/kubernetes/kube-api-server.crt \
  --kubelet-client-key=/var/lib/kubernetes/kube-api-server.key \
  --runtime-config=api/all=true \
  --service-account-key-file=/var/lib/kubernetes/service-accounts.crt \
  --service-account-signing-key-file=/var/lib/kubernetes/service-accounts.key \
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \
  --service-cluster-ip-range=10.32.0.0/24 \
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \
  --tls-cert-file=/var/lib/kubernetes/kube-api-server.crt \
  --tls-private-key-file=/var/lib/kubernetes/kube-api-server.key \
  --secure-port=6443 \
  --bind-address=0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > units/kube-controller-manager.service <<'EOF'
[Unit]
Description=Kubernetes Controller Manager
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --bind-address=0.0.0.0 \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.crt \
  --cluster-signing-key-file=/var/lib/kubernetes/ca.key \
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \
  --leader-elect=true \
  --root-ca-file=/var/lib/kubernetes/ca.crt \
  --service-account-private-key-file=/var/lib/kubernetes/service-accounts.key \
  --use-service-account-credentials=true
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > units/kube-scheduler.service <<'EOF'
[Unit]
Description=Kubernetes Scheduler
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-scheduler --config=/etc/kubernetes/config/kube-scheduler.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > units/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/containerd
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

cat > units/kubelet.service <<'EOF'
[Unit]
Description=Kubelet
After=network.target containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \
  --config=/var/lib/kubelet/kubelet-config.yaml \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --container-runtime=remote \
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \
  --network-plugin=cni \
  --register-node=true
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > units/kube-proxy.service <<'EOF'
[Unit]
Description=Kube Proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# RBAC apiserver -> kubelet
cat > configs/kube-apiserver-to-kubelet.yaml <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups: [""]
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - kind: User
    name: kube-apiserver
    apiGroup: rbac.authorization.k8s.io
EOF

# Encryption config plantilla
cat > configs/encryption-config.yaml.tpl <<'EOF'
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: __ENC_KEY__
      - identity: {}
EOF

############################################
# 7) CA y certificados
############################################
echo "Generando CA y certificados..."
cd "$WORKDIR"
# Rellena ca.conf con dominio e IP server
sed -e "s/__BASEDOM__/${BASEDOM}/g" -e "s/__SERVER_IP__/${SERVER_IP}/g" configs/ca.conf > ca.conf

# CA
openssl genrsa -out ca.key 4096
openssl req -x509 -new -sha512 -noenc -key ca.key -days 3653 -config ca.conf -extensions v3_ca -out ca.crt

gen_cert(){
  local name="$1" section="$2" exts="$3"
  openssl genrsa -out "${name}.key" 4096
  openssl req -new -key "${name}.key" -sha256 -config ca.conf -section "${section}" -out "${name}.csr"
  openssl x509 -req -days 3653 -in "${name}.csr" -sha256 -CA ca.crt -CAkey ca.key -CAcreateserial -extfile ca.conf -extensions "${exts}" -out "${name}.crt"
}

# server-side
gen_cert "kube-api-server" "kube-api-server" "v3_ext_server"
gen_cert "kube-controller-manager" "kube-controller-manager" "v3_ext_client"
gen_cert "kube-scheduler" "kube-scheduler" "v3_ext_client"
gen_cert "kube-proxy" "kube-proxy" "v3_ext_client"
gen_cert "service-accounts" "service-accounts" "v3_ext_client"
gen_cert "admin" "admin" "v3_ext_client"

# Nodos: certificados tipo client con CN system:node:<name> y O=system:nodes
for idx in "${!W_NAMES[@]}"; do
  N="${W_NAMES[$idx]}"
  cat > "node-${N}.conf" <<EOF
[req]
prompt = no
distinguished_name = dn
req_extensions = v3_ext_client
[dn]
CN = system:node:${N}
O = system:nodes
OU = kthw
EOF
  openssl genrsa -out "${N}.key" 4096
  openssl req -new -key "${N}.key" -sha256 -config "node-${N}.conf" -out "${N}.csr"
  openssl x509 -req -days 3653 -in "${N}.csr" -sha256 -CA ca.crt -CAkey ca.key -CAcreateserial -extfile ca.conf -extensions v3_ext_client -out "${N}.crt"
done

############################################
# 8) kubeconfigs
############################################
echo "Creando kubeconfigs..."
KCTX="kubernetes-the-hard-way"
APISERVER_URL="https://${SERVER_FQDN}:6443"

kubectl_bin="$WORKDIR/downloads/client/kubectl"

# worker kubeconfig
for idx in "${!W_NAMES[@]}"; do
  N="${W_NAMES[$idx]}"
  "$kubectl_bin" config set-cluster "${KCTX}" \
    --certificate-authority=ca.crt --embed-certs=true \
    --server="${APISERVER_URL}" \
    --kubeconfig="${N}.kubeconfig"
  "$kubectl_bin" config set-credentials "system:node:${N}" \
    --client-certificate="${N}.crt" --client-key="${N}.key" \
    --embed-certs=true --kubeconfig="${N}.kubeconfig"
  "$kubectl_bin" config set-context default --cluster="${KCTX}" --user="system:node:${N}" --kubeconfig="${N}.kubeconfig"
  "$kubectl_bin" config use-context default --kubeconfig="${N}.kubeconfig"
done

# kube-proxy
"$kubectl_bin" config set-cluster "${KCTX}" --certificate-authority=ca.crt --embed-certs=true --server="${APISERVER_URL}" --kubeconfig=kube-proxy.kubeconfig
"$kubectl_bin" config set-credentials system:kube-proxy --client-certificate=kube-proxy.crt --client-key=kube-proxy.key --embed-certs=true --kubeconfig=kube-proxy.kubeconfig
"$kubectl_bin" config set-context default --cluster="${KCTX}" --user=system:kube-proxy --kubeconfig=kube-proxy.kubeconfig
"$kubectl_bin" config use-context default --kubeconfig=kube-proxy.kubeconfig

# controller-manager
"$kubectl_bin" config set-cluster "${KCTX}" --certificate-authority=ca.crt --embed-certs=true --server="${APISERVER_URL}" --kubeconfig=kube-controller-manager.kubeconfig
"$kubectl_bin" config set-credentials system:kube-controller-manager --client-certificate=kube-controller-manager.crt --client-key=kube-controller-manager.key --embed-certs=true --kubeconfig=kube-controller-manager.kubeconfig
"$kubectl_bin" config set-context default --cluster="${KCTX}" --user=system:kube-controller-manager --kubeconfig=kube-controller-manager.kubeconfig
"$kubectl_bin" config use-context default --kubeconfig=kube-controller-manager.kubeconfig

# scheduler
"$kubectl_bin" config set-cluster "${KCTX}" --certificate-authority=ca.crt --embed-certs=true --server="${APISERVER_URL}" --kubeconfig=kube-scheduler.kubeconfig
"$kubectl_bin" config set-credentials system:kube-scheduler --client-certificate=kube-scheduler.crt --client-key=kube-scheduler.key --embed-certs=true --kubeconfig=kube-scheduler.kubeconfig
"$kubectl_bin" config set-context default --cluster="${KCTX}" --user=system:kube-scheduler --kubeconfig=kube-scheduler.kubeconfig
"$kubectl_bin" config use-context default --kubeconfig=kube-scheduler.kubeconfig

# admin (para usar en server localhost)
"$kubectl_bin" config set-cluster "${KCTX}" --certificate-authority=ca.crt --embed-certs=true --server="https://127.0.0.1:6443" --kubeconfig=admin.kubeconfig
"$kubectl_bin" config set-credentials admin --client-certificate=admin.crt --client-key=admin.key --embed-certs=true --kubeconfig=admin.kubeconfig
"$kubectl_bin" config set-context default --cluster="${KCTX}" --user=admin --kubeconfig=admin.kubeconfig
"$kubectl_bin" config use-context default --kubeconfig=admin.kubeconfig

############################################
# 9) Encryption config
############################################
ENC_KEY="$(head -c 32 /dev/urandom | base64)"
sed "s/__ENC_KEY__/${ENC_KEY}/" configs/encryption-config.yaml.tpl > encryption-config.yaml

############################################
# 10) Copia artefactos a server
############################################
echo "Instalando en server..."
# Binarios
scp_to "${SERVER_IP}" "/usr/local/bin/" "$WORKDIR/downloads/controller/etcd"
scp_to "${SERVER_IP}" "/usr/local/bin/" "$WORKDIR/downloads/controller/etcdctl"
scp_to "${SERVER_IP}" "/usr/local/bin/" "$WORKDIR/downloads/controller/kube-apiserver"
scp_to "${SERVER_IP}" "/usr/local/bin/" "$WORKDIR/downloads/controller/kube-controller-manager"
scp_to "${SERVER_IP}" "/usr/local/bin/" "$WORKDIR/downloads/controller/kube-scheduler"
scp_to "${SERVER_IP}" "/usr/local/bin/" "$WORKDIR/downloads/client/kubectl"
run "${SERVER_IP}" "chmod +x /usr/local/bin/etcd* /usr/local/bin/kube*"

# Certs y configs
for f in ca.crt ca.key kube-api-server.crt kube-api-server.key service-accounts.crt service-accounts.key encryption-config.yaml kube-controller-manager.kubeconfig kube-scheduler.kubeconfig admin.kubeconfig; do
  scp_to "${SERVER_IP}" "~/${f}" "$WORKDIR/${f}"
done

# Estructura
run "${SERVER_IP}" "mkdir -p /etc/kubernetes/config /var/lib/kubernetes /etc/etcd /var/lib/etcd && chmod 700 /var/lib/etcd"
run "${SERVER_IP}" "mv ~/ca.crt ~/ca.key ~/kube-api-server.crt ~/kube-api-server.key ~/service-accounts.crt ~/service-accounts.key ~/encryption-config.yaml /var/lib/kubernetes/"
run "${SERVER_IP}" "cp /var/lib/kubernetes/ca.crt /etc/etcd/ && cp /var/lib/kubernetes/kube-api-server.crt /etc/etcd/ && cp /var/lib/kubernetes/kube-api-server.key /etc/etcd/"
scp_to "${SERVER_IP}" "/etc/kubernetes/config/" "$WORKDIR/configs/kube-scheduler.yaml"
run "${SERVER_IP}" "mv ~/kube-controller-manager.kubeconfig ~/kube-scheduler.kubeconfig /var/lib/kubernetes/"

# Units
scp_to "${SERVER_IP}" "/etc/systemd/system/" "$WORKDIR/units/etcd.service"
# kube-apiserver.service con IP expandida
tmp_unit="/tmp/kas.$$"
sed "s/__SERVER_IP__/${SERVER_IP}/" units/kube-apiserver.service.tpl > "$tmp_unit"
scp_to "${SERVER_IP}" "/etc/systemd/system/kube-apiserver.service" "$tmp_unit"
rm -f "$tmp_unit"
scp_to "${SERVER_IP}" "/etc/systemd/system/" "$WORKDIR/units/kube-controller-manager.service"
scp_to "${SERVER_IP}" "/etc/systemd/system/" "$WORKDIR/units/kube-scheduler.service"

# Arranque
run "${SERVER_IP}" "systemctl daemon-reload && systemctl enable etcd && systemctl start etcd"
# Verificación etcd
run "${SERVER_IP}" "ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints=http://127.0.0.1:2379 endpoint health"

run "${SERVER_IP}" "systemctl enable kube-apiserver kube-controller-manager kube-scheduler && systemctl start kube-apiserver kube-controller-manager kube-scheduler"
# Espera apiserver
echo "Esperando kube-apiserver..."
for i in {1..60}; do
  set +e
  run "${SERVER_IP}" "KUBECONFIG=~/admin.kubeconfig kubectl version --short" && { set -e; break; }
  set -e
  sleep 2
done
run "${SERVER_IP}" "systemctl is-active kube-apiserver kube-controller-manager kube-scheduler"

# RBAC apiserver -> kubelet
scp_to "${SERVER_IP}" "~/kube-apiserver-to-kubelet.yaml" "$WORKDIR/configs/kube-apiserver-to-kubelet.yaml"
run "${SERVER_IP}" "KUBECONFIG=~/admin.kubeconfig kubectl apply -f ~/kube-apiserver-to-kubelet.yaml"

############################################
# 11) Prepara y configura WORKERS
############################################
echo "Instalando en workers..."
for idx in "${!W_NAMES[@]}"; do
  N="${W_NAMES[$idx]}"; IP="${W_IPS[$idx]}"; SUB="${W_PODS[$idx]}"

  # Copia binarios
  scp_to "${IP}" "/usr/local/bin/" "$WORKDIR/downloads/worker/kubelet"
  scp_to "${IP}" "/usr/local/bin/" "$WORKDIR/downloads/worker/kube-proxy"
  scp_to "${IP}" "/usr/local/bin/" "$WORKDIR/downloads/worker/runc.${ARCH_GO}"
  scp_to "${IP}" "/usr/local/bin/" "$WORKDIR/downloads/worker/crictl"
  run "${IP}" "mv /usr/local/bin/runc.${ARCH_GO} /usr/local/bin/runc && chmod +x /usr/local/bin/*"

  # containerd a /usr (para /usr/bin/containerd)
  scp_to "${IP}" "/tmp/containerd.tar.gz" "$WORKDIR/downloads/containerd-${CONTAINERD_VER}-linux-${ARCH_GO}.tar.gz"
  run "${IP}" "tar -C /usr -xzf /tmp/containerd.tar.gz"

  # CNI plugins
  run "${IP}" "mkdir -p /opt/cni/bin /etc/cni/net.d /var/lib/{kubelet,kube-proxy,kubernetes} /var/run/kubernetes"
  scp_to "${IP}" "/opt/cni/bin/" "$WORKDIR/downloads/cni-plugins/*"

  # Configs kubelet/kube-proxy/CNI
  kl_cfg="/tmp/kubelet-config-${N}.yaml"; cni_bridge="/tmp/10-bridge-${N}.conf"
  sed "s|SUBNET|${SUB}|g" configs/10-bridge.conf.tpl > "$cni_bridge"
  sed 'p' configs/kubelet-config.yaml.tpl > "$kl_cfg"  # copia

  scp_to "${IP}" "/var/lib/kubelet/kubelet-config.yaml" "$kl_cfg"
  scp_to "${IP}" "/var/lib/kube-proxy/kube-proxy-config.yaml" "$WORKDIR/configs/kube-proxy-config.yaml"
  scp_to "${IP}" "/etc/cni/net.d/10-bridge.conf" "$cni_bridge"
  scp_to "${IP}" "/etc/cni/net.d/99-loopback.conf" "$WORKDIR/configs/99-loopback.conf"

  # Certs y kubeconfigs del nodo
  scp_to "${IP}" "/var/lib/kubelet/ca.crt" "$WORKDIR/ca.crt"
  scp_to "${IP}" "/var/lib/kubelet/kubelet.crt" "$WORKDIR/${N}.crt"
  scp_to "${IP}" "/var/lib/kubelet/kubelet.key" "$WORKDIR/${N}.key"
  scp_to "${IP}" "/var/lib/kubelet/kubeconfig" "$WORKDIR/${N}.kubeconfig"
  scp_to "${IP}" "/var/lib/kube-proxy/kubeconfig" "$WORKDIR/kube-proxy.kubeconfig"

  # Units y containerd config
  scp_to "${IP}" "/etc/systemd/system/" "$WORKDIR/units/containerd.service"
  scp_to "${IP}" "/etc/systemd/system/" "$WORKDIR/units/kubelet.service"
  scp_to "${IP}" "/etc/systemd/system/" "$WORKDIR/units/kube-proxy.service"
  scp_to "${IP}" "/etc/containerd/config.toml" "$WORKDIR/configs/containerd-config.toml"

  # Kernel y sysctl
  run "${IP}" "modprobe br_netfilter || true; echo br_netfilter > /etc/modules-load.d/k8s.conf"
  run "${IP}" "cat >/etc/sysctl.d/99-kubernetes.conf <<SYS
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
SYS
sysctl --system >/dev/null 2>&1 || true"

  # Dependencias
  run "${IP}" "apt-get update && apt-get -y install socat conntrack ipset kmod iptables"

  # Permisos claves
  run "${IP}" "chmod 600 /var/lib/kubelet/kubelet.key || true"

  # Arranque
  run "${IP}" "systemctl daemon-reload && systemctl enable containerd kubelet kube-proxy && systemctl start containerd kubelet kube-proxy"
  run "${IP}" "systemctl is-active containerd kubelet kube-proxy"
done

############################################
# 12) Rutas estáticas entre subredes de Pods
############################################
echo "Añadiendo rutas estáticas..."
# En server, rutas a cada subred vía IP del worker
for idx in "${!W_IPS[@]}"; do
  run "${SERVER_IP}" "ip route replace ${W_PODS[$idx]} via ${W_IPS[$idx]}"
done
# Entre workers (malla mínima)
for i in "${!W_IPS[@]}"; do
  for j in "${!W_IPS[@]}"; do
    [[ "$i" == "$j" ]] && continue
    run "${W_IPS[$i]}" "ip route replace ${W_PODS[$j]} via ${W_IPS[$j]}"
  done
done

############################################
# 13) kubectl desde jumpbox (opcional)
############################################
echo "Configurando kubectl en jumpbox..."
install -m 0755 "$WORKDIR/downloads/client/kubectl" /usr/local/bin/kubectl
kubectl config set-cluster "${KCTX}" --certificate-authority="$WORKDIR/ca.crt" --embed-certs=true --server="${APISERVER_URL}"
kubectl config set-credentials admin --client-certificate="$WORKDIR/admin.crt" --client-key="$WORKDIR/admin.key" --embed-certs=true
kubectl config set-context "${KCTX}" --cluster="${KCTX}" --user=admin
kubectl config use-context "${KCTX}"

############################################
# 14) Smoke tests
############################################
echo "Esperando nodos Ready..."
for i in {1..60}; do
  READY="$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | grep -c '^Ready$' || true)"
  [[ "$READY" -ge "${WORKER_COUNT}" ]] && break
  sleep 2
done
kubectl get nodes

# Encriptación de Secrets
kubectl create secret generic kubernetes-the-hard-way --from-literal="mykey=mydata" --dry-run=client -o yaml | kubectl apply -f -
run "${SERVER_IP}" "ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2379 get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C | head -n 5"

# nginx de prueba
kubectl create deployment nginx --image=nginx:latest --replicas=1
for i in {1..60}; do
  kubectl get pods -l app=nginx -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running && break || true
  sleep 2
done
kubectl expose deployment nginx --port 80 --type NodePort
NODE_PORT="$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')"
POD_NODE="$(kubectl get pods -l app=nginx -o jsonpath='{.items[0].spec.nodeName}')"
NODE_IP="$(for idx in "${!W_NAMES[@]}"; do [[ "${W_NAMES[$idx]}" == "${POD_NODE}" ]] && echo "${W_IPS[$idx]}"; done)"
echo "Probar: curl -I http://${NODE_IP}:${NODE_PORT}"

echo "OK. Cluster listo."
