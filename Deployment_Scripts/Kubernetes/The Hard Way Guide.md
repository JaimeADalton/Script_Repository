¡Perfecto! Empezar con Kubernetes puede ser desafiante, pero con esta guía vamos paso a paso y aprenderás muchísimo en el proceso.

🚀 **¿Qué vamos a hacer?**

Vas a montar tu propio clúster de Kubernetes desde cero, a mano, usando el tutorial “Kubernetes The Hard Way”. Es ideal si quieres aprender en profundidad cómo funciona.

🛠️ **Requisitos iniciales**

Para comenzar, necesitas 4 máquinas (físicas o virtuales), todas con Debian 12 (bookworm). Pueden ser:

*   Máquinas virtuales con VirtualBox, VMware, Proxmox, QEMU, o en la nube (DigitalOcean, AWS, etc.).
*   Raspberry Pis (si estás en ARM64).
*   Tu propio equipo, usando herramientas como multipass o Vagrant.

Las 4 máquinas serán:

| Nombre  | Rol                     | CPU | RAM   | Disco | Notas                       |
| :------ | :---------------------- | :-- | :---- | :---- | :-------------------------- |
| jumpbox | Máquina de administración | 1   | 512MB | 10GB  | Desde aquí ejecutamos todo  |
| server  | Plano de control        | 1   | 2GB   | 20GB  | Ejecuta API, etcd, etc.     |
| node-0  | Nodo de trabajo         | 1   | 2GB   | 20GB  | Ejecuta pods                |
| node-1  | Nodo de trabajo         | 1   | 2GB   | 20GB  | Ejecuta pods                |

🧭 **PASO A PASO**

Te ayudaré paso por paso, empezando por el primero.

✅ **Paso 1: Prepara las máquinas**

Asumimos que ya tienes las 4 máquinas corriendo Debian 12 con acceso SSH como root. ¡Excelente! 🎉 Ya con las 4 máquinas listas, ahora comenzamos oficialmente el tutorial.

✅ **Paso 2: Configurar el jumpbox**

Tu máquina `jumpbox` será tu centro de control. Desde aquí ejecutarás casi todos los comandos.

🔧 **1. Accede como root**

En tu terminal:

```bash
ssh root@IP_DEL_JUMPBOX
```

(reemplaza `IP_DEL_JUMPBOX` con la IP real de tu jumpbox)

🔧 **2. Instala herramientas básicas**

Una vez dentro de la máquina:

```bash
apt-get update
apt-get install -y wget curl vim openssl git
```

🔧 **3. Clona el repositorio del tutorial**

```bash
git clone --depth 1 https://github.com/kelseyhightower/kubernetes-the-hard-way.git
cd kubernetes-the-hard-way
```

Este directorio (`/root/kubernetes-the-hard-way`) será donde trabajes durante toda la instalación.

🔧 **4. Descarga los binarios**

Ya que usas ARM64 o AMD64, detectamos automáticamente qué descargar:

```bash
ARCH=$(dpkg --print-architecture)
wget -q --show-progress --https-only --timestamping \
  -P downloads -i downloads-${ARCH}.txt
```

Luego extrae y organiza los binarios:

```bash
mkdir -p downloads/{client,cni-plugins,controller,worker}

tar -xvf downloads/crictl-v*.tar.gz -C downloads/worker/
tar -xvf downloads/containerd-v*.tar.gz --strip-components=1 -C downloads/worker/
tar -xvf downloads/cni-plugins-linux-${ARCH}-v*.tgz -C downloads/cni-plugins/
tar -xvf downloads/etcd-v*.tar.gz -C downloads/ \
  --strip-components 1 etcd-v*/etcdctl etcd-v*/etcd

mv downloads/{etcdctl,kubectl} downloads/client/
mv downloads/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler} downloads/controller/
mv downloads/{kubelet,kube-proxy} downloads/worker/
mv downloads/runc.${ARCH} downloads/worker/runc # Ajustado para que coincida con el original

chmod +x downloads/{client,cni-plugins,controller,worker}/*
rm -rf downloads/*gz # Limpia los archivos tar.gz descargados
```

🔧 **5. Instala kubectl en el sistema**

```bash
cp downloads/client/kubectl /usr/local/bin/
```

Verifica que funcione:

```bash
kubectl version --client
```

Debe mostrar algo como:

```
Client Version: v1.32.3
```

✅ **Paso 3: Provisionar las máquinas (server, node-0, node-1)**

🔹 **Objetivo**

*   Crear un archivo `machines.txt` con info de tus nodos.
*   Configurar acceso SSH por clave pública desde el `jumpbox` a `server`, `node-0` y `node-1`.
*   Asignar nombres (hostname) a cada máquina (`server`, `node-0`, `node-1`).
*   Actualizar `/etc/hosts` en todas las máquinas (`jumpbox`, `server`, `node-0`, `node-1`) para que todas puedan resolverse entre sí por nombre.

🧾 **1. Crea el archivo `machines.txt`**

Desde tu `jumpbox`, en el directorio `kubernetes-the-hard-way`, crea el archivo con este formato:

```
IPV4_ADDRESS FQDN HOSTNAME POD_SUBNET
```

Ejemplo (reemplaza las IPs y FQDNs con los tuyos si son diferentes):

```bash
cat > machines.txt <<EOF
192.168.1.10 server.kubernetes.local server
192.168.1.11 node-0.kubernetes.local node-0 10.200.0.0/24
192.168.1.12 node-1.kubernetes.local node-1 10.200.1.0/24
EOF
```

✏️ Modifica las IPs, FQDNs y subredes si las tuyas son distintas. La columna `POD_SUBNET` solo es necesaria para los nodos worker.

🔑 **2. Habilitar acceso SSH como root (si no está ya habilitado)**

En cada nodo (`server`, `node-0`, `node-1`), haz esto si es necesario:

Accede a cada máquina con tu usuario normal y luego cambia a root:
`su - root`

Luego edita `/etc/ssh/sshd_config`:

```bash
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart sshd
```

Esto permite que puedas conectar desde el `jumpbox` como root.

🔐 **3. Generar y distribuir claves SSH (desde el jumpbox)**

En tu `jumpbox`:

```bash
ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
```

Ahora copia la clave pública a los nodos (`server`, `node-0`, `node-1`):

```bash
while read IP FQDN HOST SUBNET; do
  ssh-copy-id root@${IP}
done < machines.txt
```

Verifica el acceso SSH sin contraseña:

```bash
while read IP FQDN HOST SUBNET; do
  ssh -n root@${IP} hostname
done < machines.txt
```

Debe devolver:

```
server
node-0
node-1
```

🏷️ **4. Configura los hostnames (desde el jumpbox)**

```bash
while read IP FQDN HOST SUBNET; do
  ssh -n root@${IP} "sed -i 's/^127.0.1.1.*/127.0.1.1\t${FQDN} ${HOST}/' /etc/hosts"
  ssh -n root@${IP} "hostnamectl set-hostname ${HOST}"
  ssh -n root@${IP} "systemctl restart systemd-hostnamed"
done < machines.txt
```

Verifica:

```bash
while read IP FQDN HOST SUBNET; do
  ssh -n root@${IP} hostname --fqdn
done < machines.txt
```

Debe devolver:

```
server.kubernetes.local
node-0.kubernetes.local
node-1.kubernetes.local
```

🧭 **5. Configura `/etc/hosts` en todas las máquinas (jumpbox, server, node-0, node-1)**

En el `jumpbox`, crea un archivo `hosts` temporal que contenga las entradas para todas las máquinas del clúster:

```bash
echo "" > hosts
echo "# Kubernetes The Hard Way Cluster" >> hosts
while read IP FQDN HOST SUBNET; do
  ENTRY="${IP} ${FQDN} ${HOST}"
  echo ${ENTRY} >> hosts
done < machines.txt
```

Revisa el archivo `hosts` generado:

```bash
cat hosts
```

Debería verse así (con tus IPs):

```
# Kubernetes The Hard Way Cluster
192.168.1.10 server.kubernetes.local server
192.168.1.11 node-0.kubernetes.local node-0
192.168.1.12 node-1.kubernetes.local node-1
```

Añade estas entradas al `/etc/hosts` del `jumpbox`:

```bash
cat hosts >> /etc/hosts
```

Ahora, copia el archivo `hosts` temporal a cada una de las máquinas del clúster (`server`, `node-0`, `node-1`) y añade su contenido a sus respectivos `/etc/hosts`:

```bash
while read IP FQDN HOST SUBNET; do
  scp hosts root@${HOST}:~/
  ssh -n root@${HOST} "cat ~/hosts >> /etc/hosts"
done < machines.txt
```

Verifica que puedes hacer ping por nombre desde el `jumpbox` a las otras máquinas y entre ellas. Por ejemplo, desde `jumpbox`:

```bash
ping -c 1 server
ping -c 1 node-0
ping -c 1 node-1
```

Y desde `server`, intenta hacer ping a `node-0`, etc.

✅ ¡Listo! Tus máquinas ya se pueden comunicar entre sí por nombre (`server`, `node-0`, `node-1`).

✅ **Paso 4: Crear CA y certificados TLS** 🔐

Esto es uno de los pasos más técnicos, pero te lo voy a guiar muy claro.

📦 **Objetivo**

Desde el `jumpbox`:

*   Crear una CA propia.
*   Generar certificados firmados para:
    *   `kube-apiserver`, `kubelet`, `kube-proxy`, etc.
    *   `admin` (usuario de `kubectl`)
*   Distribuir los certificados a las máquinas correspondientes.

🧰 **1. Asegúrate de estar en el directorio correcto**

En el `jumpbox`:

```bash
cd ~/kubernetes-the-hard-way
```

🛡️ **2. Generar la Autoridad Certificadora (CA)**

Primero, genera la clave privada de la CA:

```bash
openssl genrsa -out ca.key 4096
```

Luego, el certificado autofirmado:

```bash
openssl req -x509 -new -sha512 -noenc \
  -key ca.key -days 3653 \
  -config ca.conf \
  -out ca.crt
```

📝 Esto usará el archivo `ca.conf` ya incluido, que define cómo debe generarse cada certificado del clúster.

📄 **3. Generar certificados para todos los componentes**

Ejecuta esto (copia completo):

```bash
certs=(
  "admin" "node-0" "node-1"
  "kube-proxy" "kube-scheduler"
  "kube-controller-manager"
  "kube-api-server"
  "service-accounts"
)

for i in ${certs[*]}; do
  openssl genrsa -out "${i}.key" 4096

  openssl req -new -key "${i}.key" -sha256 \
    -config "ca.conf" -section ${i} \
    -out "${i}.csr"

  openssl x509 -req -days 3653 -in "${i}.csr" \
    -copy_extensions copyall \
    -sha256 -CA "ca.crt" \
    -CAkey "ca.key" \
    -CAcreateserial \
    -out "${i}.crt"
done
```

Verifica que se hayan creado:

```bash
ls -1 *.crt *.key *.csr
```

📤 **4. Copiar certificados a los nodos**

➤ A los workers (`node-0`, `node-1`):

```bash
for host in node-0 node-1; do
  ssh root@${host} "mkdir -p /var/lib/kubelet/"
  scp ca.crt root@${host}:/var/lib/kubelet/
  scp ${host}.crt root@${host}:/var/lib/kubelet/kubelet.crt
  scp ${host}.key root@${host}:/var/lib/kubelet/kubelet.key
done
```

➤ Al control plane (`server`):

```bash
scp \
  ca.key ca.crt \
  kube-api-server.key kube-api-server.crt \
  service-accounts.key service-accounts.crt \
  root@server:~/
```

✅ ¡Listo! Ya tienes certificados seguros generados y distribuidos.

✅ **Paso 5: Archivos kubeconfig para autenticación** 📁

Los archivos `kubeconfig` permiten que los componentes de Kubernetes (y usuarios como `admin`) se comuniquen con el `kube-apiserver` de forma segura, usando los certificados TLS que generaste en el paso anterior.

🧰 **¿Dónde correr esto?**

Ejecuta todos los comandos de este paso desde el `jumpbox`, dentro del directorio `kubernetes-the-hard-way`.

```bash
cd ~/kubernetes-the-hard-way
```

🔹 **1. Generar kubeconfig para los nodos (`node-0` y `node-1`)**

```bash
for host in node-0 node-1; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://server.kubernetes.local:6443 \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-credentials system:node:${host} \
    --client-certificate=${host}.crt \
    --client-key=${host}.key \
    --embed-certs=true \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${host} \
    --kubeconfig=${host}.kubeconfig

  kubectl config use-context default \
    --kubeconfig=${host}.kubeconfig
done
```

🔹 **2. `kube-proxy.kubeconfig`**

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://server.kubernetes.local:6443 \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=kube-proxy.crt \
  --client-key=kube-proxy.key \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default \
  --kubeconfig=kube-proxy.kubeconfig
```

🔹 **3. `kube-controller-manager.kubeconfig`**

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://server.kubernetes.local:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=kube-controller-manager.crt \
  --client-key=kube-controller-manager.key \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context default \
  --kubeconfig=kube-controller-manager.kubeconfig
```

🔹 **4. `kube-scheduler.kubeconfig`**

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://server.kubernetes.local:6443 \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.crt \
  --client-key=kube-scheduler.key \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default \
  --kubeconfig=kube-scheduler.kubeconfig
```

🔹 **5. `admin.kubeconfig`**

Este es el que usarás tú como administrador.

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=admin.crt \
  --client-key=admin.key \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context default \
  --kubeconfig=admin.kubeconfig
```

📤 **6. Distribuir kubeconfig a las máquinas**

➤ A los nodos (`node-0`, `node-1`):

```bash
for host in node-0 node-1; do
  ssh root@${host} "mkdir -p /var/lib/{kube-proxy,kubelet}"

  scp kube-proxy.kubeconfig \
    root@${host}:/var/lib/kube-proxy/kubeconfig

  scp ${host}.kubeconfig \
    root@${host}:/var/lib/kubelet/kubeconfig
done
```

➤ Al `server`:

```bash
scp admin.kubeconfig \
  kube-controller-manager.kubeconfig \
  kube-scheduler.kubeconfig \
  root@server:~/
```

✅ ¡Y listo! Ya tienes todos los `kubeconfig` generados y en su lugar.

✅ **Paso 6: Crear clave de encriptación para secretos (`encryption-config.yaml`)** 🔐

Kubernetes permite encriptar los `Secrets` almacenados en `etcd`. En este paso:

*   Generamos una clave de encriptación segura.
*   Creamos un archivo de configuración para usarla.
*   La copiamos al servidor de control (`server`).

🧰 **¿Dónde hacerlo?**

Todo este paso se hace desde el `jumpbox`.

🔹 **1. Generar una clave segura**

Ejecuta:

```bash
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
```

Puedes verificar que se creó:

```bash
echo $ENCRYPTION_KEY
```

🔹 **2. Generar el archivo `encryption-config.yaml`**

El archivo ya está preparado como plantilla en `configs/encryption-config.yaml`, con la variable `${ENCRYPTION_KEY}`.

Usa `envsubst` para reemplazar esa variable:

```bash
envsubst < configs/encryption-config.yaml > encryption-config.yaml
```

Esto generará un archivo real con la clave insertada.

Verifica que esté bien:

```bash
cat encryption-config.yaml
```

Deberías ver algo así:

```yaml
kind: EncryptionConfiguration
apiVersion: apiserver.config.k8s.io/v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: TU_CLAVE_GENERADA_AQUI
      - identity: {}
```

🔹 **3. Copiar a la máquina `server`**

```bash
scp encryption-config.yaml root@server:~/
```

✅ ¡Enhorabuena! Ya tienes el archivo de configuración de encriptación listo. Este archivo será usado por el `kube-apiserver`.

✅ **Paso 7: Bootstrapping de etcd** 📦

`etcd` es una base de datos distribuida clave-valor que almacena el estado de todo el clúster de Kubernetes. Aquí lo desplegaremos en modo de nodo único (solo en el `server`).

🧰 **¿Dónde hacerlo?**

Este paso se hace dentro del nodo `server`. Así que primero conéctate a él desde el `jumpbox`:

```bash
ssh root@server
```

Una vez dentro del `server`:

🔹 **1. Instalar los binarios de `etcd`**

Desde el `jumpbox`, ya copiaste los binarios necesarios (`etcd`, `etcdctl`) y el archivo de servicio `etcd.service` al directorio home del `server` en pasos anteriores (implícito en la estructura del tutorial, si no, asegúrate de que estén copiados):

Comandos a ejecutar en el `server`:

```bash
# Mueve los binarios (asumiendo que están en ~/)
mv ~/etcd ~/etcdctl /usr/local/bin/
chmod +x /usr/local/bin/etcd*
```

🔹 **2. Configurar `etcd`**

Crea las carpetas necesarias:

```bash
mkdir -p /etc/etcd /var/lib/etcd
chmod 700 /var/lib/etcd
```

Copia los certificados necesarios (ya deben estar en tu home del `server` desde el Paso 4):

```bash
cp ~/ca.crt ~/kube-api-server.crt ~/kube-api-server.key /etc/etcd/
```

🔹 **3. Instalar el servicio de `systemd`**

Mueve el archivo de servicio (asumiendo que está en `~/`):

```bash
mv ~/etcd.service /etc/systemd/system/
```

Puedes verificar su contenido si quieres:

```bash
cat /etc/systemd/system/etcd.service
```

🔹 **4. Iniciar `etcd`**

Recarga `systemd` y habilita el servicio:

```bash
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd
```

Verifica el estado:

```bash
systemctl status etcd
```

Debería mostrar `active (running)`.

🔎 **5. Verificar que `etcd` funciona**

Usa `etcdctl` para listar los miembros del clúster:

```bash
ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.crt \
  --cert=/etc/etcd/kube-api-server.crt \
  --key=/etc/etcd/kube-api-server.key
```
(Nota: El tutorial original usa HTTP para etcd en su configuración de servicio, así que el comando sería más simple si se mantiene esa configuración. El archivo `units/etcd.service` usa `http://127.0.0.1:2379` y `http://127.0.0.1:2380`. Si es así, el comando de verificación es:)

```bash
etcdctl member list
```

Deberías ver algo como:

```
ID, STATUS, NAME, PEER ADDRS, CLIENT ADDRS, IS LEARNER
xxxxxxxxxxxxxxxx, started, controller, http://127.0.0.1:2380, http://127.0.0.1:2379, false
```

Sal del `server` para volver al `jumpbox` (`exit`).

✅ ¡Listo! `etcd` está funcionando como backend de almacenamiento para Kubernetes.

✅ **Paso 8: Bootstrapping del Control Plane** 🧠

Instalaremos en el nodo `server` los tres componentes principales del plano de control:

| Componente                | Rol principal                        |
| :------------------------ | :----------------------------------- |
| `kube-apiserver`          | Punto central de comunicación del clúster |
| `kube-controller-manager` | Gestiona controladores internos      |
| `kube-scheduler`          | Asigna pods a nodos disponibles      |

🧰 **¿Dónde se hace?**

Todo este paso se ejecuta en el nodo `server`. Conéctate desde el `jumpbox`:

```bash
ssh root@server
```

Una vez dentro del `server`:

🔹 **1. Crear carpeta de configuración**

```bash
mkdir -p /etc/kubernetes/config
```

🔹 **2. Instalar los binarios**

Desde el `jumpbox` ya copiaste los binarios y archivos de configuración necesarios al directorio home del `server` en pasos anteriores.

Comandos a ejecutar en el `server`:

```bash
# Mueve los binarios (asumiendo que están en ~/)
mv ~/kube-apiserver ~/kube-controller-manager ~/kube-scheduler ~/kubectl /usr/local/bin/
chmod +x /usr/local/bin/kube*
```

🔹 **3. Configurar `kube-apiserver`**

Crear carpeta:

```bash
mkdir -p /var/lib/kubernetes/
```

Mover los certificados y configuración (asumiendo que están en `~/`):

```bash
mv ~/ca.crt ~/ca.key \
   ~/kube-api-server.key ~/kube-api-server.crt \
   ~/service-accounts.key ~/service-accounts.crt \
   ~/encryption-config.yaml \
   /var/lib/kubernetes/
```

Mover archivo de servicio:

```bash
mv ~/kube-apiserver.service /etc/systemd/system/kube-apiserver.service
```

🔹 **4. Configurar `kube-controller-manager`**

Mover el `kubeconfig` (asumiendo que está en `~/`):

```bash
mv ~/kube-controller-manager.kubeconfig /var/lib/kubernetes/
```

Mover unit file:

```bash
mv ~/kube-controller-manager.service /etc/systemd/system/
```

🔹 **5. Configurar `kube-scheduler`**

Mover el `kubeconfig` (asumiendo que está en `~/`):

```bash
mv ~/kube-scheduler.kubeconfig /var/lib/kubernetes/
```

Mover el archivo YAML de configuración (asumiendo que está en `~/`):

```bash
mv ~/kube-scheduler.yaml /etc/kubernetes/config/
```

Mover unit file:

```bash
mv ~/kube-scheduler.service /etc/systemd/system/
```

🔹 **6. Iniciar los servicios del control plane**

```bash
systemctl daemon-reload
systemctl enable kube-apiserver kube-controller-manager kube-scheduler
systemctl start kube-apiserver kube-controller-manager kube-scheduler
```

Verifica que estén activos (espera unos segundos para que inicien):

```bash
systemctl is-active kube-apiserver
systemctl is-active kube-controller-manager
systemctl is-active kube-scheduler
```

Todos deben devolver `active`. Si no, revisa los logs con `journalctl -u <nombre-del-servicio>`.

🔎 **7. Comprobar con `kubectl` (usando el `admin.kubeconfig`)**

```bash
kubectl cluster-info --kubeconfig ~/admin.kubeconfig
```

Deberías ver algo como:

```
Kubernetes control plane is running at https://127.0.0.1:6443
```

🔐 **8. Habilitar permisos del API Server para acceder a `kubelets`**

Aplica la configuración RBAC (asumiendo `kube-apiserver-to-kubelet.yaml` está en `~/`):

```bash
kubectl apply -f ~/kube-apiserver-to-kubelet.yaml \
  --kubeconfig ~/admin.kubeconfig
```

Sal del `server` para volver al `jumpbox` (`exit`).

✅ ¡Listo! Tu control plane está instalado y funcionando 🚀

✅ **Paso 9: Bootstrapping de los nodos Worker (`node-0` y `node-1`)** ⚙️

En este paso vas a instalar en cada nodo worker:

| Componente      | Función principal                        |
| :-------------- | :--------------------------------------- |
| `containerd`    | Ejecuta contenedores                     |
| `runc`          | Ejecuta contenedores compatibles con OCI |
| `kubelet`       | Agente que corre en cada nodo            |
| `kube-proxy`    | Administra la red de servicios           |
| `CNI Plugins`   | Red entre pods                           |

🔧 **¿Cómo lo haremos?**

*   Desde el `jumpbox` copiarás binarios y config a los workers.
*   Luego entrarás a cada worker (`node-0` y `node-1`) y ejecutarás comandos para instalarlos.

🧰 **Parte 1: Preparar desde el `jumpbox`**

🔹 **1. Personaliza y copia configuración de red (`10-bridge.conf` y `kubelet-config.yaml`)**:

```bash
for HOST in node-0 node-1; do
  SUBNET=$(grep ${HOST} machines.txt | cut -d " " -f 4) # Asegúrate que machines.txt tenga la 4ta columna con la subred del pod

  # Crea archivos de configuración personalizados para cada nodo
  sed "s|SUBNET|${SUBNET}|g" configs/10-bridge.conf > 10-bridge-${HOST}.conf
  # kubelet-config.yaml no parece tener un placeholder SUBNET en el original, pero si lo tuviera, se haría igual.
  # Si no hay placeholder, se copia el mismo archivo.
  cp configs/kubelet-config.yaml kubelet-config-${HOST}.yaml

  scp 10-bridge-${HOST}.conf root@${HOST}:~/10-bridge.conf
  scp kubelet-config-${HOST}.yaml root@${HOST}:~/kubelet-config.yaml

  # Limpia los archivos temporales
  rm 10-bridge-${HOST}.conf kubelet-config-${HOST}.yaml
done
```

🔹 **2. Copia binarios y unidades `systemd`**:

```bash
for HOST in node-0 node-1; do
  scp \
    downloads/worker/* \
    downloads/client/kubectl \
    configs/99-loopback.conf \
    configs/containerd-config.toml \
    configs/kube-proxy-config.yaml \
    units/containerd.service \
    units/kubelet.service \
    units/kube-proxy.service \
    root@${HOST}:~/
done
```

🔹 **3. Copia plugins CNI**:

```bash
for HOST in node-0 node-1; do
  ssh root@${HOST} "mkdir -p ~/cni-plugins/"
  scp downloads/cni-plugins/* root@${HOST}:~/cni-plugins/
done
```

🧱 **Parte 2: En cada nodo worker (`node-0` y luego `node-1`)**

Ahora, entra uno por uno. Primero a `node-0`:

```bash
ssh root@node-0
```

Y ejecuta los siguientes comandos. Luego, sal y repite los mismos comandos en `node-1`.

🔹 **1. Instala dependencias del sistema**

```bash
apt-get update
apt-get -y install socat conntrack ipset kmod
```

🔹 **2. Desactiva el swap**

```bash
swapoff -a
# Y comenta la línea de swap en /etc/fstab para que sea persistente
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

Verifica:

```bash
swapon --show
```
(No debería mostrar nada)

🔹 **3. Crea los directorios**

```bash
mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes
```

🔹 **4. Instala los binarios (asumiendo que están en `~/`)**

```bash
mv ~/crictl ~/kube-proxy ~/kubelet ~/runc /usr/local/bin/
mv ~/containerd ~/containerd-shim-runc-v2 ~/containerd-stress /bin/ # Ajustado según el tutorial
mv ~/cni-plugins/* /opt/cni/bin/
chmod +x /usr/local/bin/* /bin/containerd* /opt/cni/bin/*
```

🔹 **5. Configura red (CNI)**

Mueve los archivos de configuración CNI (asumiendo que están en `~/`):

```bash
mv ~/10-bridge.conf ~/99-loopback.conf /etc/cni/net.d/
```

Activa módulo de red:

```bash
modprobe br_netfilter # Corregido: guion bajo en lugar de guion
echo "br_netfilter" >> /etc/modules-load.d/modules.conf
```

Habilita `iptables` para el bridge:

```bash
echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/kubernetes.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/kubernetes.conf
sysctl -p /etc/sysctl.d/kubernetes.conf
```

🔹 **6. Configura `containerd`**

```bash
mkdir -p /etc/containerd/
mv ~/containerd-config.toml /etc/containerd/config.toml
mv ~/containerd.service /etc/systemd/system/
```

🔹 **7. Configura `kubelet`**

Mueve `kubelet-config.yaml` (asumiendo que está en `~/`) y `kubelet.service`:

```bash
mv ~/kubelet-config.yaml /var/lib/kubelet/
# También necesitas el kubeconfig del kubelet y el ca.crt que copiaste en el Paso 4 y Paso 5
# Estos ya deberían estar en /var/lib/kubelet/ (ca.crt, kubelet.crt, kubelet.key) y
# /var/lib/kubelet/kubeconfig
mv ~/kubelet.service /etc/systemd/system/
```

🔹 **8. Configura `kube-proxy`**

Mueve `kube-proxy-config.yaml` (asumiendo que está en `~/`) y `kube-proxy.service`:

```bash
mv ~/kube-proxy-config.yaml /var/lib/kube-proxy/
# kube-proxy también necesita su kubeconfig, ya copiado en /var/lib/kube-proxy/kubeconfig en el Paso 5
mv ~/kube-proxy.service /etc/systemd/system/
```

🔹 **9. Inicia los servicios**

```bash
systemctl daemon-reload
systemctl enable containerd kubelet kube-proxy
systemctl start containerd kubelet kube-proxy
```

Verifica:

```bash
systemctl is-active kubelet
systemctl is-active containerd
systemctl is-active kube-proxy
```

Todos deben devolver `active`.

Sal de `node-0` (`exit`) y **repite todos estos pasos de la "Parte 2" en `node-1`**.

🔁 **Verifica desde el servidor (`server`)**

Vuelve al `jumpbox` y conéctate al `server`:

```bash
ssh root@server
```

Luego, usa el `admin.kubeconfig` (que debería estar en `~/admin.kubeconfig` en el `server`):

```bash
kubectl get nodes --kubeconfig ~/admin.kubeconfig
```

Debes ver ambos nodos, y después de unos momentos, deberían pasar a `Ready`:

```
NAME     STATUS   ROLES    AGE   VERSION
node-0   Ready    <none>   1m    v1.32.3
node-1   Ready    <none>   10s   v1.32.3
```
(La edad y el estado pueden variar inicialmente)

Sal del `server` (`exit`).

✅ ¡Tus nodos worker ya están funcionando! 🎉

✅ **Paso 10: Configurar `kubectl` en el `jumpbox` para acceso remoto**

Este paso te permite usar `kubectl` directamente desde el `jumpbox`, sin tener que estar en el nodo `server`.

🔧 **1. En el `jumpbox`, instala el archivo `kubeconfig` de `admin`**

Asegúrate de tener los certificados `admin.crt`, `admin.key`, y `ca.crt` en el directorio actual (`~/kubernetes-the-hard-way`) del `jumpbox`.

Ejecuta (estos comandos crean `~/.kube/config`):

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=https://server.kubernetes.local:6443

kubectl config set-credentials admin \
  --client-certificate=admin.crt \
  --client-key=admin.key

kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin

kubectl config use-context kubernetes-the-hard-way
```

Esto crea un archivo `~/.kube/config` con los datos necesarios para `kubectl`.

🔍 **2. Verificar conectividad con el servidor**

```bash
kubectl version
```

Deberías ver algo como:

```
Client Version: v1.32.3
Server Version: v1.32.3
```

🔍 **3. Verificar estado del clúster**

```bash
kubectl get nodes
```

Debe devolver:

```
NAME     STATUS   ROLES    AGE   VERSION
node-0   Ready    <none>   ...   v1.32.3
node-1   Ready    <none>   ...   v1.32.3
```

🎉 ¡Y listo! Ya puedes administrar tu clúster con `kubectl` desde el `jumpbox`.

✅ **Paso 11: Rutas de red entre Pods** 🌐

Kubernetes asigna a cada nodo un rango de IPs (subred) para sus Pods. Pero, por defecto, no existen rutas entre esas subredes en diferentes máquinas, así que los Pods no pueden comunicarse entre nodos. Este paso corrige eso añadiendo rutas manuales.

🗺️ **Supuestos**

Según tu `machines.txt` (ejemplo):

*   `node-0`: subred `10.200.0.0/24`, IP `192.168.1.11`
*   `node-1`: subred `10.200.1.0/24`, IP `192.168.1.12`

Ajusta las IPs y subredes a las tuyas.

🔧 **Paso a paso (ejecutar desde el `jumpbox`)**

🔹 **1. Añadir rutas en el `server` para los workers**

```bash
# Variables para IPs y Subredes (ajusta si tu machines.txt es diferente o no está disponible)
NODE_0_IP=$(grep node-0 machines.txt | cut -d " " -f 1)
NODE_0_SUBNET=$(grep node-0 machines.txt | cut -d " " -f 4)
NODE_1_IP=$(grep node-1 machines.txt | cut -d " " -f 1)
NODE_1_SUBNET=$(grep node-1 machines.txt | cut -d " " -f 4)

ssh root@server <<EOF
ip route add ${NODE_0_SUBNET} via ${NODE_0_IP}
ip route add ${NODE_1_SUBNET} via ${NODE_1_IP}
EOF
```

🔹 **2. Añadir rutas en `node-0` hacia `node-1`**

```bash
ssh root@node-0 "ip route add ${NODE_1_SUBNET} via ${NODE_1_IP}"
```

🔹 **3. Añadir rutas en `node-1` hacia `node-0`**

```bash
ssh root@node-1 "ip route add ${NODE_0_SUBNET} via ${NODE_0_IP}"
```

🧪 **Verifica las rutas**

Ejemplo en el `server`:

```bash
ssh root@server ip route
```

Deberías ver algo como (interfaz `ensX` puede variar):

```
...
10.200.0.0/24 via 192.168.1.11 dev ensX
10.200.1.0/24 via 192.168.1.12 dev ensX
...
```
Verifica también en `node-0` y `node-1`.

✅ ¡Listo! Ahora los Pods podrán comunicarse entre nodos a través de sus IPs internas.

✅ **Paso 12: Smoke Test** 🔥

Este es el momento de la verdad: vamos a comprobar que el clúster funciona de verdad ejecutando workloads reales.

🧰 **¿Dónde ejecutar todo esto?**

Desde el `jumpbox`, usando `kubectl`.

Asegúrate de tener configurado el archivo `~/.kube/config` correctamente (lo hiciste en el paso 10).

🔹 **1. Crear un Secret y verificar que esté cifrado**

```bash
kubectl create secret generic kubernetes-the-hard-way \
  --from-literal="mykey=mydata"
```

Ahora desde el `server`, verifica que esté cifrado en `etcd`:

```bash
ssh root@server \
  'etcdctl get /registry/secrets/default/kubernetes-the-hard-way | hexdump -C'
```

🔍 Busca que la salida comience con algo como:

```
... k8s:enc:aescbc:v1:key1:...
```

✅ Eso confirma que los Secrets se están almacenando cifrados.

🔹 **2. Crear un Deployment (`nginx`)**

```bash
kubectl create deployment nginx --image=nginx:latest
```

Verifica (espera a que el pod esté `Running`):

```bash
kubectl get pods -l app=nginx
```

Debes ver el pod corriendo:

```
NAME                     READY   STATUS    RESTARTS   AGE
nginx-xxxxxxx-xxxxx      1/1     Running   0          Xs
```

🔹 **3. Port-forward para probar HTTP**

```bash
POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $POD_NAME 8080:80
```

En **otra terminal** en tu `jumpbox`, ejecuta:

```bash
curl --head http://127.0.0.1:8080
```

✅ Deberías recibir un `HTTP/1.1 200 OK`.

Vuelve a la terminal del `port-forward` y presiona `Ctrl+C` para detenerlo.

🔹 **4. Leer logs del pod**

```bash
kubectl logs $POD_NAME
```

Verás logs de acceso, por ejemplo, del `curl`.

🔹 **5. Ejecutar un comando dentro del contenedor**

```bash
kubectl exec -ti $POD_NAME -- nginx -v
```

Debe mostrar la versión de `nginx`, por ejemplo:

```
nginx version: nginx/1.2x.x
```

🔹 **6. Exponer el servicio vía `NodePort`**

```bash
kubectl expose deployment nginx \
  --port 80 \
  --type NodePort
```

Verifica el puerto asignado:

```bash
NODE_PORT=$(kubectl get svc nginx \
  --output=jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort asignado: $NODE_PORT"
```

Ahora identifica en qué nodo está corriendo el pod:

```bash
NODE_NAME=$(kubectl get pods -l app=nginx \
  -o jsonpath="{.items[0].spec.nodeName}")
echo "nginx está corriendo en: $NODE_NAME (IP: $(grep $NODE_NAME machines.txt | cut -d ' ' -f1))"
# Necesitas la IP del nodo, no el nombre para el curl.
NODE_IP=$(grep $NODE_NAME machines.txt | cut -d ' ' -f1)
```

Haz la prueba accediendo al servicio usando la IP de uno de tus nodos (`node-0` o `node-1`) y el `NodePort`:

```bash
curl -I http://${NODE_IP}:${NODE_PORT}
```

✅ Deberías obtener otro `HTTP/1.1 200 OK`.

🎉 ¡Clúster funcionando correctamente!

✅ **Paso 13: Limpieza del clúster** 🧹

Este paso es opcional, pero útil si ya terminaste tus pruebas o quieres liberar recursos.

🔹 **¿Qué se limpia?**

*   Las instancias de máquinas del `server`, `node-0`, `node-1` (no el `jumpbox`, si quieres repetir).
*   No se requiere eliminar configuraciones a mano — basta con borrar las VMs.

🧨 **Cómo hacerlo**

Si estás en un entorno local o virtualizado (ej. Proxmox, VirtualBox, VMware):

🔻 Simplemente elimina las 3 máquinas virtuales:

*   `server`
*   `node-0`
*   `node-1`

Si estás en la nube (AWS, GCP, etc.), destruye los recursos (VMs, discos, redes) que creaste manualmente.

🧼 **Opcional: Limpia el entorno del `jumpbox`**

Si también quieres limpiar el `jumpbox`, puedes borrar el directorio de trabajo:

```bash
rm -rf ~/kubernetes-the-hard-way
```
Y el `~/.kube/config`:
```bash
rm -f ~/.kube/config
```

✅ ¡Todo limpio!

🎓 **¡Felicidades!**

Has completado Kubernetes The Hard Way, instalando todo a mano:

*   Certificados TLS
*   `etcd`
*   Control Plane (`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`)
*   Workers (`kubelet`, `kube-proxy`, `containerd`)
*   Redes CNI
*   Acceso RBAC
*   `kubectl` desde el `jumpbox`
*   Smoke test con éxito

🚀 Entiendes lo que pasa “bajo el capó” de Kubernetes. Muchos usan `kubeadm` o `k3s`, pero tú ahora sabes cómo funciona de verdad.

---

**Automatización de la Instalación**

Ahora que has completado la instalación manual de Kubernetes siguiendo el enfoque de "The Hard Way", es natural buscar formas de automatizar este proceso para futuras implementaciones. Existen varias guías y proyectos que replican este enfoque utilizando herramientas como Ansible y Terraform, manteniendo la filosofía de comprender cada componente del clúster.

🛠️ **Opciones para Automatizar la Instalación de Kubernetes**

1.  **Automatización con Ansible: `kubernetes-hard-way-ansible`**

    Este proyecto de `zufardhiyaulhaq` automatiza la instalación de Kubernetes siguiendo el enfoque de "The Hard Way" utilizando Ansible. Incluye soporte para Vagrant y OpenID Connect (OIDC), y proporciona funcionalidades para renovar certificados, añadir nuevos nodos worker y actualizar la versión de Kubernetes.

    *   **Características principales**:
        *   Automatización completa de la instalación de Kubernetes (versión específica del proyecto).
        *   Soporte para Flannel, CNI, `containerd`, `runc` y otros componentes esenciales.
        *   Playbooks para tareas comunes como renovación de certificados y adición de nodos.
    *   **Pasos generales**:
        *   Preparar el entorno de Ansible en el nodo de despliegue.
        *   Configurar el inventario de hosts y variables de grupo.
        *   Ejecutar el playbook principal para desplegar el clúster.
    *   **Repositorio**: [kubernetes-hard-way-ansible en GitHub](https://github.com/zufardhiyaulhaq/kubernetes-hard-way-ansible)

2.  **Automatización con Terraform y Ansible en AWS**

    El equipo de OpenCredo ha desarrollado una guía detallada para desplegar un clúster de Kubernetes en AWS utilizando Terraform para la provisión de infraestructura y Ansible para la configuración del clúster. Este enfoque automatiza los pasos de "The Hard Way" adaptándolos a un entorno en la nube.

    *   **Características principales**:
        *   Provisión de infraestructura en AWS con Terraform (VPC, subredes, instancias EC2).
        *   Configuración de Kubernetes con Ansible, incluyendo `etcd`, control plane y nodos worker.
        *   Despliegue de un servicio de ejemplo (`nginx`) para verificar el funcionamiento del clúster.
    *   **Pasos generales**:
        *   Utilizar Terraform para crear la infraestructura necesaria en AWS.
        *   Aplicar playbooks de Ansible para instalar y configurar Kubernetes en las instancias creadas.
    *   **Guía detallada**: [Kubernetes from scratch to AWS with Terraform and Ansible (part 1)](https://medium.com/@opencredo/kubernetes-from-scratch-to-aws-with-terraform-and-ansible-part-1-a7549f3a8a0f)
    *   **Repositorio**: [k8s-terraform-ansible-sample en GitHub](https://github.com/opencredo/k8s-terraform-ansible-sample)

3.  **Automatización Local con Terraform y Ansible**

    Si prefieres un entorno local, este tutorial de Kraven Security muestra cómo desplegar un clúster de Kubernetes utilizando Terraform y Ansible en un entorno local, como Proxmox. Este enfoque es ideal para laboratorios y pruebas en entornos controlados.

    *   **Características principales**:
        *   Provisión de máquinas virtuales locales con Terraform.
        *   Configuración de Kubernetes con Ansible, a menudo usando `kubeadm` para simplificar ciertas partes pero manteniendo el control sobre la infraestructura.
        *   Despliegue de aplicaciones de ejemplo para verificar el funcionamiento del clúster.
    *   **Pasos generales**:
        *   Utilizar Terraform para crear las máquinas virtuales necesarias.
        *   Aplicar playbooks de Ansible para instalar y configurar Kubernetes en las VMs.
        *   Desplegar aplicaciones de prueba y verificar la conectividad.
    *   **Guía detallada**: [How To Create A Local Kubernetes Cluster: Terraform And Ansible](https://kravensecurity.com/how-to-create-a-local-kubernetes-cluster-terraform-and-ansible/)

🔍 **Comparativa de Enfoques**

| Proyecto                                 | Herramientas        | Entorno       | Características destacadas                                     |
| :--------------------------------------- | :------------------ | :------------ | :------------------------------------------------------------- |
| `kubernetes-hard-way-ansible`            | Ansible             | Local/Vagrant | Automatización completa siguiendo "The Hard Way"               |
| OpenCredo: Terraform + Ansible en AWS    | Terraform, Ansible  | AWS           | Provisión y configuración automatizada en la nube             |
| Kraven Security: Terraform + Ansible local | Terraform, Ansible  | Local         | Despliegue local ideal para laboratorios y pruebas (puede usar `kubeadm`) |

✅ **Recomendación**

Dado que ya has realizado la instalación manual y estás familiarizado con los componentes de Kubernetes, te recomiendo explorar el proyecto `kubernetes-hard-way-ansible`. Este proyecto automatiza el proceso que ya conoces, permitiéndote comparar cada paso y entender cómo se traduce en tareas de Ansible.

Si deseas experimentar con la automatización en la nube, la guía de OpenCredo es una excelente opción para aplicar estos conocimientos en un entorno AWS.
