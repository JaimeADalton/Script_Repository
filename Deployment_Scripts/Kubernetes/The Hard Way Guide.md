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

---

**Manual Teórico de "Kubernetes The Hard Way": Comprendiendo los Cimientos**

**Introducción: ¿Por Qué "The Hard Way" y Qué Aprenderemos?**

"Kubernetes The Hard Way" no es la forma más rápida de tener un clúster funcional, ¡pero sí una de las más enriquecedoras! Al construir cada componente manualmente, desmitificamos la "magia" de Kubernetes. Este manual teórico te acompañará en ese viaje, explicando los conceptos detrás de cada acción práctica.

**Objetivo de este Manual Teórico:**

1.  **Entender la Arquitectura de Kubernetes:** Visualizar cómo los componentes interactúan.
2.  **Comprender la Seguridad:** Por qué los certificados y la encriptación son cruciales.
3.  **Asimilar el Flujo de Trabajo:** Desde la solicitud de un Pod hasta su ejecución.
4.  **Conocer los Primitivos de Red:** Cómo se comunican los Pods y Servicios.
5.  **Valorar la Automatización:** Entender qué problemas resuelven herramientas como `kubeadm` después de haberlo hecho a mano.

---

**Parte I: Preparación y Cimientos de la Infraestructura**

**Capítulo 1: Las Máquinas – El Lienzo de Nuestro Clúster (Corresponde al Paso 1 Práctico)**

*   **¿Por qué máquinas dedicadas (virtuales o físicas)?**
    Kubernetes es un sistema distribuido. Necesita múltiples "ordenadores" (nodos) para funcionar.
    *   **Plano de Control (`server`):** Es el cerebro. Aquí residen los componentes que toman decisiones globales sobre el clúster (ej. dónde ejecutar una aplicación, cómo mantener el número deseado de réplicas). Separarlo de los nodos de trabajo es una práctica estándar para la estabilidad y seguridad.
    *   **Nodos de Trabajo (`node-0`, `node-1`):** Son los músculos. Aquí es donde tus aplicaciones (contenedores dentro de Pods) realmente se ejecutan. Necesitamos al menos uno, pero dos o más nos permiten ver cómo Kubernetes distribuye la carga y maneja fallos.
    *   **Jumpbox:** Es nuestra "mesa de operaciones". Centraliza las herramientas, binarios y configuraciones. Evita instalar todo en cada máquina del clúster o en tu máquina personal, manteniendo el entorno limpio y reproducible.
*   **¿Por qué Debian 12 (Bookworm)?**
    Es una distribución de Linux estable, popular y con buen soporte comunitario. Podríamos usar otras (CentOS, Ubuntu), pero para un tutorial, la consistencia es clave. Lo importante es un kernel de Linux moderno y herramientas estándar.
*   **¿Por qué acceso `root`?**
    Para este tutorial, usamos `root` por conveniencia, ya que instalaremos software a nivel de sistema, modificaremos archivos de configuración críticos y gestionaremos servicios. **En un entorno de producción, NUNCA se trabajaría directamente como `root` para todo.** Se usaría `sudo` con permisos específicos o herramientas de gestión de configuración que operan con privilegios elevados de forma controlada.

**Capítulo 2: El Jumpbox – Nuestro Centro de Comando (Corresponde al Paso 2 Práctico)**

*   **Herramientas Básicas (`wget`, `curl`, `vim`, `openssl`, `git`):**
    *   `wget`/`curl`: Para descargar archivos de internet (los binarios de Kubernetes).
    *   `vim`: Un editor de texto para modificar archivos de configuración (puedes usar `nano` u otro).
    *   `openssl`: Herramienta fundamental para crear y gestionar certificados TLS/SSL, la base de la comunicación segura.
    *   `git`: Para clonar el repositorio de "Kubernetes The Hard Way", que contiene plantillas y la estructura del tutorial.
*   **Descarga Centralizada de Binarios:**
    *   **¿Qué son estos binarios?** Son los programas ejecutables que componen Kubernetes:
        *   `etcd`: La base de datos del clúster.
        *   `kube-apiserver`: El frontal de la API, el punto de entrada principal.
        *   `kube-controller-manager`: Vigila el estado y ejecuta bucles de reconciliación.
        *   `kube-scheduler`: Decide en qué nodo se ejecuta un Pod.
        *   `kubelet`: Agente en cada nodo worker, gestiona los Pods en ese nodo.
        *   `kube-proxy`: Gestiona las reglas de red en cada nodo para los Servicios.
        *   `kubectl`: La herramienta de línea de comandos para interactuar con el clúster.
        *   `containerd`, `runc`, `crictl`: Componentes del runtime de contenedores.
        *   Plugins CNI: Para la red de los Pods.
    *   **¿Por qué descargarlos en el Jumpbox?**
        1.  **Consistencia de Versión:** Asegura que todas las máquinas del clúster usen exactamente la misma versión de cada componente. Esto es vital para evitar incompatibilidades.
        2.  **Eficiencia:** Se descargan una sola vez, ahorrando ancho de banda y tiempo.
*   **Versiones Específicas:** Kubernetes evoluciona rápidamente. Un tutorial como este fija versiones específicas para garantizar que los pasos sean reproducibles. Las APIs y comportamientos pueden cambiar entre versiones.

**Capítulo 3: Provisionamiento de Nodos – Identidad y Conectividad (Corresponde al Paso 3 Práctico)**

*   **Archivo `machines.txt`:**
    Actúa como una mini-base de datos para nuestro clúster. Almacena información crucial (IP, nombre de host, FQDN, subred de Pods) que usaremos repetidamente en scripts y configuraciones.
*   **SSH Keys (Claves SSH):**
    *   **¿Por qué?** Para una comunicación segura y automatizada entre el `jumpbox` y los nodos del clúster. En lugar de escribir contraseñas cada vez, usamos un par de claves criptográficas (pública y privada). La clave pública se instala en los nodos, y solo el `jumpbox` (que tiene la clave privada) puede autenticarse.
    *   Es la base para que herramientas de automatización (como Ansible, que veremos al final) puedan gestionar múltiples servidores.
*   **Hostnames (Nombres de Host):**
    *   **¿Por qué?** Los humanos (y los sistemas) prefieren nombres a direcciones IP. `server.kubernetes.local` es más fácil de recordar y gestionar que `192.168.1.10`.
    *   Muchos componentes de Kubernetes se referenciarán entre sí usando estos nombres. Los certificados TLS también validarán estos nombres.
*   **`/etc/hosts`:**
    *   **¿Qué es?** Un archivo local que mapea nombres de host a direcciones IP. Actúa como un mini-DNS local.
    *   **¿Por qué modificarlo en TODAS las máquinas?** Cada máquina del clúster (incluido el `jumpbox`) necesita poder resolver los nombres de las otras máquinas. Si `node-0` necesita hablar con `server.kubernetes.local`, debe saber qué IP corresponde a ese nombre.
    *   **Alternativa en Producción:** En entornos más grandes o de producción, se usaría un servidor DNS centralizado en lugar de modificar `/etc/hosts` en cada máquina. Para nuestro tutorial, `/etc/hosts` es más simple.

---

**Parte II: Seguridad – La Columna Vertebral del Clúster**

**Capítulo 4: Autoridad Certificadora (CA) y Certificados TLS (Corresponde al Paso 4 Práctico)**

*   **¿Qué es TLS/SSL?**
    Transport Layer Security (TLS) –sucesor de Secure Sockets Layer (SSL)– es un protocolo criptográfico que proporciona comunicaciones seguras a través de una red. Ofrece:
    1.  **Autenticación:** Verifica la identidad de las partes que se comunican (¿realmente estoy hablando con el `kube-apiserver`?).
    2.  **Encriptación:** Cifra los datos transmitidos para que no puedan ser leídos por terceros.
    3.  **Integridad:** Asegura que los datos no hayan sido manipulados durante la transmisión.
*   **¿Por qué Kubernetes necesita TLS?**
    Todos los componentes de Kubernetes se comunican a través de la red (incluso si están en la misma máquina, a través de `localhost`). Esta comunicación incluye información sensible (configuraciones, secretos, órdenes). Sin TLS, esta comunicación sería vulnerable a escuchas (eavesdropping) y ataques de "hombre en el medio" (man-in-the-middle).
*   **Autoridad Certificadora (CA):**
    *   **¿Qué es?** Es una entidad de confianza que emite y firma certificados digitales. Un certificado digital vincula una identidad (como `kube-apiserver`) a una clave pública.
    *   **Nuestra CA autofirmada:** En este tutorial, creamos nuestra propia CA. Esto significa que nosotros somos la raíz de confianza. Todos los componentes del clúster confiarán en los certificados emitidos por *nuestra* CA.
    *   **Producción:** En producción, podrías usar una CA interna de tu organización o incluso certificados de CAs públicas para componentes expuestos a internet (aunque esto es menos común para la comunicación interna del clúster).
*   **Certificados para cada Componente:**
    Cada componente principal (`kube-apiserver`, `kubelet`, `etcd`, `kube-proxy`, `kube-controller-manager`, `kube-scheduler`) y el usuario `admin` obtienen su propio par de clave privada y certificado firmado por nuestra CA.
    *   **Identidad Única:** Esto les da una identidad única.
    *   **Autenticación Mutua (mTLS):** A menudo, no solo el cliente verifica al servidor, sino que el servidor también verifica al cliente. Por ejemplo, el `kube-apiserver` necesita saber que está hablando con un `kubelet` legítimo, y el `kubelet` necesita saber que está hablando con el `kube-apiserver` legítimo.
*   **`ca.conf` – El Molde de los Certificados:**
    Este archivo de configuración de OpenSSL define las propiedades de cada certificado:
    *   `CN (Common Name)`: El nombre principal del certificado (ej. `kube-apiserver` o `system:node:node-0`). Es crucial para la identificación y, en algunos casos (como los `kubelets`), para la autorización RBAC.
    *   `O (Organization)`: Usado para agrupar entidades. En Kubernetes, `O=system:masters` otorga privilegios de administrador de clúster, y `O=system:nodes` es para los `kubelets`.
    *   `SAN (Subject Alternative Name)`: Permite especificar múltiples nombres de host y direcciones IP para los cuales el certificado es válido. Esto es vital, ya que el `kube-apiserver`, por ejemplo, puede ser accedido por `127.0.0.1`, su IP de red, `kubernetes.default.svc.cluster.local`, etc.
*   **Distribución de Certificados:**
    Cada componente necesita acceso a:
    1.  Su propia clave privada (`componente.key`).
    2.  Su propio certificado (`componente.crt`).
    3.  El certificado de la CA (`ca.crt`) para poder verificar los certificados de otros componentes.
    Las claves privadas deben mantenerse seguras y solo accesibles por el componente que las usa.

**Capítulo 5: Archivos `kubeconfig` – Las Llaves de Acceso (Corresponde al Paso 5 Práctico)**

*   **¿Qué es un archivo `kubeconfig`?**
    Es un archivo YAML que contiene la información necesaria para que un cliente (como `kubectl` o un componente de Kubernetes) se conecte y autentique con un clúster de Kubernetes, específicamente con su `kube-apiserver`.
*   **Componentes Clave de un `kubeconfig`:**
    1.  **Clusters:** Define los clústeres disponibles. Cada clúster tiene:
        *   `server`: La URL del `kube-apiserver`.
        *   `certificate-authority-data`: El certificado de la CA del clúster (embebido y codificado en base64) para que el cliente pueda verificar el certificado del `kube-apiserver`.
    2.  **Users:** Define las identidades de usuario. Cada usuario tiene:
        *   `client-certificate-data`: El certificado del cliente (embebido, base64).
        *   `client-key-data`: La clave privada del cliente (embebida, base64).
        *   (Alternativamente, podría usar tokens).
    3.  **Contexts:** Vincula un `user` con un `cluster` (y opcionalmente un `namespace` por defecto). Es la "conexión activa".
    4.  `current-context`: Especifica qué contexto usar por defecto.
*   **¿Por qué un `kubeconfig` para cada componente?**
    *   **`kubelet`:** Necesita un `kubeconfig` para registrarse con el `kube-apiserver`, enviar el estado del nodo y de los Pods, y obtener las especificaciones de los Pods que debe ejecutar. Su identidad (definida por su certificado `system:node:<nombre-nodo>`) es usada por el Node Authorizer y RBAC.
    *   **`kube-proxy`:** Necesita un `kubeconfig` para obtener información sobre Servicios y Endpoints del `kube-apiserver` y así poder configurar las reglas de red (`iptables`).
    *   **`kube-controller-manager` y `kube-scheduler`:** Necesitan `kubeconfigs` para interactuar con el `kube-apiserver`, observar el estado del clúster y realizar cambios (crear/actualizar objetos).
    *   **`admin`:** El `kubeconfig` para el usuario administrador, permitiéndole usar `kubectl` para gestionar el clúster. La URL del servidor aquí es `https://127.0.0.1:6443` porque este `kubeconfig` específico se usa *dentro* del nodo `server`.
*   **`embed-certs=true`:**
    Hace que el `kubeconfig` sea autocontenido al incrustar los datos de los certificados directamente en el archivo, en lugar de referenciar archivos externos. Esto facilita su distribución.

**Capítulo 6: Encriptación de Secretos en Reposo (Corresponde al Paso 6 Práctico)**

*   **¿Qué son los `Secrets` de Kubernetes?**
    Son objetos de Kubernetes diseñados para almacenar pequeñas cantidades de datos sensibles, como contraseñas, tokens OAuth o claves SSH.
*   **¿Por qué encriptarlos "en reposo"?**
    "En reposo" significa que los datos están encriptados mientras están almacenados en la base de datos persistente del clúster, que es `etcd`. Si un atacante obtuviera acceso directo a los archivos de `etcd` (por ejemplo, a una copia de seguridad), los `Secrets` no estarían en texto plano. Es una capa adicional de seguridad (defensa en profundidad).
*   **¿Cómo funciona?**
    1.  Cuando creas un `Secret` a través del `kube-apiserver`.
    2.  El `kube-apiserver`, antes de escribirlo en `etcd`, lo encripta usando una clave y un proveedor de encriptación configurados.
    3.  Cuando se lee un `Secret`, el `kube-apiserver` lo recupera de `etcd` (donde está encriptado) y lo desencripta antes de entregarlo al cliente que lo solicitó (si está autorizado).
*   **`encryption-config.yaml`:**
    Este archivo le dice al `kube-apiserver` cómo encriptar los datos:
    *   `resources`: Especifica qué tipos de objetos encriptar (en nuestro caso, `secrets`).
    *   `providers`: Define una lista ordenada de proveedores de encriptación.
        *   `aescbc`: Utiliza el cifrado AES en modo CBC. Es un algoritmo simétrico fuerte.
            *   `keys`: Una lista de claves. `key1` es solo un nombre. El `secret` es la clave de encriptación real (generada aleatoriamente y codificada en base64). Se pueden listar múltiples claves para la rotación de claves. La primera clave de la lista se usa para encriptar. Todas las claves se pueden usar para desencriptar.
        *   `identity: {}`: Este proveedor simplemente almacena los datos tal cual (sin encriptación). Se incluye como el último de la lista para permitir la lectura de datos que podrían haber sido escritos antes de que la encriptación estuviera habilitada o con una clave diferente que ya no está.
*   **Variable de Entorno `ENCRYPTION_KEY`:**
    Se usa para generar dinámicamente el archivo `encryption-config.yaml` con una clave única cada vez que se ejecuta el tutorial. En un sistema real, esta clave se generaría y gestionaría de forma segura.

---

**Parte III: El Corazón de Kubernetes – El Plano de Control y los Nodos de Trabajo**

**Capítulo 7: `etcd` – La Fuente Única de Verdad (Corresponde al Paso 7 Práctico)**

*   **¿Qué es `etcd`?**
    Es un almacén de datos clave-valor distribuido, consistente y altamente disponible. Kubernetes lo utiliza como su base de datos principal para almacenar *todo* el estado del clúster:
    *   Configuraciones de nodos, Pods, Servicios, Deployments, Secrets, ConfigMaps, etc.
    *   Estado actual de esos objetos.
    *   Eventos del clúster.
*   **¿Por qué es tan importante?**
    Es la "fuente única de verdad". Todos los demás componentes de Kubernetes son (mayoritariamente) sin estado; leen de `etcd` para conocer el estado deseado y actual, y escriben en `etcd` para actualizar el estado. Si `etcd` se pierde y no hay copia de seguridad, todo el estado del clúster se pierde.
*   **Configuración de un solo nodo para el tutorial:**
    Por simplicidad, configuramos `etcd` en un solo nodo (`server`).
    *   **Producción:** `etcd` se ejecutaría como un clúster de 3 o 5 nodos (un número impar para el consenso Raft) para alta disponibilidad y tolerancia a fallos.
*   **Parámetros Clave de `etcd.service`:**
    *   `--name controller`: Nombre único de este miembro de `etcd` en el clúster.
    *   `--initial-advertise-peer-urls http://127.0.0.1:2380`: URL que este miembro anuncia a otros miembros para la comunicación entre pares (peer communication).
    *   `--listen-peer-urls http://127.0.0.1:2380`: URLs en las que escucha tráfico de otros miembros.
    *   `--listen-client-urls http://127.0.0.1:2379`: URLs en las que escucha tráfico de clientes (como el `kube-apiserver`).
    *   `--advertise-client-urls http://127.0.0.1:2379`: URL que este miembro anuncia a los clientes.
    *   `--initial-cluster controller=http://127.0.0.1:2380`: Define los miembros iniciales del clúster.
    *   `--data-dir=/var/lib/etcd`: Directorio donde `etcd` almacena sus datos.
*   **Seguridad de `etcd`:**
    El `etcd.service` proporcionado usa HTTP. En producción, se configuraría TLS para la comunicación con `etcd` (tanto cliente-servidor como servidor-servidor), usando certificados para autenticar al `kube-apiserver` como cliente y para que los miembros de `etcd` se autentiquen entre sí.

**Capítulo 8: El Plano de Control – El Cerebro del Clúster (Corresponde al Paso 8 Práctico)**

El plano de control está compuesto por varios componentes que se ejecutan en el nodo `server`.

1.  **`kube-apiserver`:**
    *   **Rol:** Es el componente central y el único con el que los usuarios y otros componentes interactúan directamente. Actúa como un frontend para el clúster.
        *   Expone la API REST de Kubernetes.
        *   Valida y procesa las solicitudes de API (ej. `kubectl create pod ...`).
        *   Persiste el estado de los objetos en `etcd`.
        *   Orquesta la comunicación entre componentes.
    *   **Parámetros Clave:**
        *   `--etcd-servers=http://127.0.0.1:2379`: Le dice dónde encontrar `etcd`.
        *   `--client-ca-file=/var/lib/kubernetes/ca.crt`: CA para verificar los certificados de los clientes que se conectan (ej. `kubelet`, `kubectl`).
        *   `--tls-cert-file`, `--tls-private-key-file`: Certificado y clave del propio `kube-apiserver` para servir HTTPS.
        *   `--kubelet-certificate-authority`, `--kubelet-client-certificate`, `--kubelet-client-key`: Para que el `apiserver` actúe como cliente y se conecte de forma segura a los `kubelets` (para logs, exec, etc.).
        *   `--service-account-key-file`, `--service-account-signing-key-file`, `--service-account-issuer`: Para gestionar los tokens de las [ServiceAccounts](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/) (identidades para los Pods).
        *   `--authorization-mode=Node,RBAC`:
            *   `Node`: Un autorizador especial para los `kubelets`.
            *   `RBAC (Role-Based Access Control)`: El mecanismo principal para controlar quién puede hacer qué en el clúster.
        *   `--encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml`: Apunta al archivo de configuración de encriptación de `Secrets`.
        *   `--bind-address=0.0.0.0`: Escucha en todas las interfaces de red, no solo `localhost`.
        *   `--allow-privileged=true`: Permite la ejecución de contenedores privilegiados (generalmente se necesita para algunos componentes de sistema o drivers).

2.  **`kube-controller-manager`:**
    *   **Rol:** Ejecuta varios "controladores" en segundo plano. Un controlador es un bucle que observa el estado del clúster a través del `kube-apiserver` y realiza cambios para intentar que el estado actual coincida con el estado deseado.
    *   **Ejemplos de Controladores:** Node controller (maneja nodos caídos), Replication controller (mantiene el número correcto de Pods para un ReplicaSet), Endpoint controller (popula los Endpoints para los Servicios), Service Account & Token controllers, etc.
    *   **Parámetros Clave:**
        *   `--kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig`: Le dice cómo conectarse y autenticarse con el `kube-apiserver`.
        *   `--cluster-signing-cert-file`, `--cluster-signing-key-file`: CA usada para firmar ciertos certificados generados por el clúster (como los certificados de los `kubelets` si se usa la aprobación CSR).
        *   `--root-ca-file=/var/lib/kubernetes/ca.crt`: CA raíz para verificar el `kube-apiserver`.
        *   `--service-account-private-key-file`: Clave privada para firmar tokens de ServiceAccount.
        *   `--cluster-cidr`, `--service-cluster-ip-range`: Rangos de IP para Pods y Servicios, respectivamente.

3.  **`kube-scheduler`:**
    *   **Rol:** Su única tarea es observar los Pods recién creados que aún no tienen un nodo asignado (`nodeName` vacío) y decidir en qué nodo deben ejecutarse.
    *   **Proceso de Scheduling:** Considera muchos factores: requerimientos de recursos del Pod (CPU, memoria), afinidad/anti-afinidad de nodos y Pods, taints y tolerations, disponibilidad de volúmenes, etc.
    *   **Parámetros Clave:**
        *   `--config=/etc/kubernetes/config/kube-scheduler.yaml`: Apunta a su archivo de configuración, que a su vez contiene la ruta al `kubeconfig`.
*   **`systemd` Services:**
    Usamos `systemd` para gestionar estos componentes como servicios del sistema. Esto asegura que se inicien automáticamente al arrancar la máquina y se reinicien si fallan.
*   **RBAC para `kube-apiserver` a `kubelet` (`kube-apiserver-to-kubelet.yaml`):**
    El `kube-apiserver` a veces necesita actuar como cliente y conectarse a la API de los `kubelets` (ej. para `kubectl logs`, `kubectl exec`, obtener métricas). Este archivo YAML define un `ClusterRole` (llamado `system:kube-apiserver-to-kubelet`) que otorga los permisos necesarios (acceso a `nodes/proxy`, `nodes/stats`, etc.) y un `ClusterRoleBinding` que asigna ese rol al usuario `kubernetes` (la identidad que usa el `apiserver` cuando se autentica con los `kubelets` usando su certificado cliente).

**Capítulo 9: Nodos de Trabajo – Donde la Acción Sucede (Corresponde al Paso 9 Práctico)**

Los nodos de trabajo son las máquinas donde se ejecutan tus aplicaciones.

1.  **Runtime de Contenedores (`containerd` y `runc`):**
    *   **¿Qué es un runtime de contenedores?** Es el software responsable de ejecutar y gestionar contenedores en un nodo.
    *   **`containerd`:** Es un runtime de contenedores de alto nivel, un proyecto graduado de la CNCF. Gestiona el ciclo de vida completo del contenedor en su máquina host: descarga de imágenes, gestión de almacenamiento y red para contenedores, y supervisión de la ejecución. Implementa la **CRI (Container Runtime Interface)**, que es la API que usa el `kubelet` para interactuar con el runtime.
    *   **`runc`:** Es un runtime de contenedores de bajo nivel. `containerd` lo utiliza para realmente crear y ejecutar los contenedores según la especificación OCI (Open Container Initiative). `runc` se encarga de los detalles de namespaces, cgroups, etc.
    *   **`containerd-config.toml`:** Archivo de configuración para `containerd`.
        *   `plugins."io.containerd.grpc.v1.cri"`: Configura el plugin CRI.
        *   `snapshotter = "overlayfs"`: `overlayfs` es un sistema de archivos de unión eficiente para las capas de las imágenes de contenedor.
        *   `default_runtime_name = "runc"`: Especifica que `runc` es el runtime por defecto.
        *   `SystemdCgroup = true`: Importante para que `containerd` y `kubelet` usen el mismo manejador de `cgroups` (`systemd`), evitando conflictos.
    *   **`crictl`:** Una herramienta de línea de comandos para inspeccionar y depurar runtimes compatibles con CRI (como `containerd`).

2.  **Red de Pods (CNI - Container Network Interface):**
    *   **¿Qué es CNI?** Es una especificación y un conjunto de librerías para configurar la red de los contenedores Linux. El `kubelet` invoca plugins CNI para configurar la red de cada Pod.
    *   **`10-bridge.conf` (Plugin `bridge`):**
        *   Crea un puente (bridge) de Linux llamado `cni0`.
        *   Conecta la interfaz de red del Pod (veth pair) a este puente.
        *   Asigna una IP al Pod desde la subred del nodo (`POD_SUBNET`, ej. `10.200.0.0/24`).
        *   `isGateway=true`: Hace que el puente `cni0` actúe como la puerta de enlace para los Pods en ese nodo.
        *   `ipMasq=true`: Realiza NAT (Network Address Translation) para el tráfico que sale de los Pods hacia fuera del nodo, de modo que parezca originarse desde la IP del nodo.
    *   **`99-loopback.conf` (Plugin `loopback`):** Configura la interfaz de red loopback (`lo`) dentro del Pod.
    *   **`modprobe br_netfilter` y `sysctl`:** Estos comandos aseguran que el tráfico que atraviesa el puente `cni0` sea procesado por `iptables`. Esto es necesario para que funcionen las NetworkPolicies de Kubernetes y para la correcta implementación de los Servicios.
    *   **Desactivar Swap:** Kubernetes espera un entorno de recursos predecible. El swap puede hacer que la contabilidad de memoria sea errática y llevar a un comportamiento inesperado del scheduler y del `kubelet` al aplicar límites de memoria.

3.  **`kubelet`:**
    *   **Rol:** Es el agente principal de Kubernetes que se ejecuta en cada nodo de trabajo (y también podría ejecutarse en nodos de control si estos van a correr Pods).
        *   Se registra con el `kube-apiserver`.
        *   Recibe las especificaciones de los Pods (`PodSpecs`) que se le han asignado.
        *   Interactúa con el runtime de contenedores (a través de CRI) para iniciar, detener y supervisar los contenedores de esos Pods.
        *   Monta los volúmenes de los Pods.
        *   Reporta el estado del nodo y de los Pods al `kube-apiserver`.
        *   Realiza health checks de los contenedores.
    *   **`kubelet-config.yaml`:** Su archivo de configuración.
        *   `cgroupDriver: systemd`: Debe coincidir con el `cgroupDriver` de `containerd`.
        *   `containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"`: Le dice al `kubelet` cómo comunicarse con `containerd`.
        *   `authentication` y `authorization`: Configuran cómo el `kubelet` se autentica con el `apiserver` (usando su certificado x509) y cómo se autorizan las solicitudes a la API del `kubelet` (modo `Webhook`, que delega la decisión al `apiserver`).
        *   `clientCAFile`: CA para verificar al `apiserver` cuando el `apiserver` se conecta al `kubelet`.
    *   **Certificados y `kubeconfig`:** El `kubelet` usa su propio certificado (ej. `node-0.crt`, `node-0.key`) y `kubeconfig` (ej. `node-0.kubeconfig`) para autenticarse con el `kube-apiserver`. El CN de su certificado (ej. `system:node:node-0`) es usado por el Node Authorizer.

4.  **`kube-proxy`:**
    *   **Rol:** Se ejecuta en cada nodo y es responsable de implementar la abstracción de los **Servicios** de Kubernetes.
        *   Observa al `kube-apiserver` para detectar cambios en los objetos `Service` y `Endpoint` (un `Endpoint` es una lista de IPs y puertos de los Pods que respaldan un `Service`).
        *   Mantiene reglas de red en el nodo (en nuestro caso, usando `iptables`) que redirigen el tráfico destinado a la IP virtual de un `Service` a las IPs reales de los Pods correspondientes.
    *   **`kube-proxy-config.yaml`:**
        *   `kubeconfig`: Para conectarse al `kube-apiserver`.
        *   `mode: "iptables"`: Le dice a `kube-proxy` que use `iptables` para gestionar las reglas de los Servicios. Otras opciones son `ipvs` o `userspace` (obsoleto).
        *   `clusterCIDR`: El rango de IPs general para todos los Pods en el clúster. Lo necesita para configurar correctamente `iptables` (ej. para no hacer SNAT al tráfico entre Pods).

**Capítulo 10: `kubectl` – Nuestra Interfaz al Clúster (Corresponde al Paso 10 Práctico)**

*   **¿Qué es `kubectl`?**
    Es la herramienta de línea de comandos (CLI) principal para interactuar con un clúster de Kubernetes. Permite desplegar aplicaciones, inspeccionar y gestionar recursos del clúster, ver logs, etc.
*   **Configuración Remota (`~/.kube/config` en el Jumpbox):**
    Al configurar `kubectl` en el `jumpbox` usando el certificado de `admin` y la CA del clúster, podemos gestionar el clúster remotamente.
    *   `server=https://server.kubernetes.local:6443`: Aquí es crucial que `server.kubernetes.local` sea resoluble desde el `jumpbox` (gracias a la configuración de `/etc/hosts` que hicimos) y que el certificado del `kube-apiserver` sea válido para este nombre (lo es, gracias a los SANs).
*   **Comandos Básicos de Verificación:**
    *   `kubectl version`: Muestra la versión del cliente (`kubectl`) y del servidor (`kube-apiserver`).
    *   `kubectl get nodes`: Lista los nodos del clúster y su estado. Un estado `Ready` indica que el `kubelet` está funcionando correctamente y se ha registrado.

**Capítulo 11: Red entre Pods – Habilitando la Comunicación (Corresponde al Paso 11 Práctico)**

*   **El Problema de la Comunicación Inter-Nodo:**
    *   Cada nodo tiene su propio rango de IPs para Pods (ej. `node-0` tiene `10.200.0.0/24`, `node-1` tiene `10.200.1.0/24`).
    *   Un Pod en `node-0` (ej. `10.200.0.5`) quiere hablar con un Pod en `node-1` (ej. `10.200.1.7`).
    *   Por defecto, la máquina `node-0` no sabe cómo enrutar tráfico destinado a la red `10.200.1.0/24`. Su tabla de enrutamiento local no tiene esa información.
*   **Solución en "The Hard Way" (Rutas Estáticas):**
    Añadimos manualmente rutas estáticas en cada máquina:
    *   En `server`:
        *   Para llegar a `10.200.0.0/24` (Pods en `node-0`), envía el tráfico a través de la IP de `node-0`.
        *   Para llegar a `10.200.1.0/24` (Pods en `node-1`), envía el tráfico a través de la IP de `node-1`.
    *   En `node-0`:
        *   Para llegar a `10.200.1.0/24` (Pods en `node-1`), envía el tráfico a través de la IP de `node-1`.
    *   En `node-1`:
        *   Para llegar a `10.200.0.0/24` (Pods en `node-0`), envía el tráfico a través de la IP de `node-0`.
*   **Alternativas en Producción (Plugins CNI de Red Overlay/Underlay):**
    Esta configuración manual de rutas no escala y es frágil. En producción, se utilizan plugins CNI más avanzados que crean una red virtual (overlay network) o se integran con la red física (underlay network) para gestionar este enrutamiento automáticamente. Ejemplos: Flannel, Calico, Weave Net, Cilium. Estos plugins se encargan de que cada Pod pueda alcanzar a cualquier otro Pod usando su IP, sin importar en qué nodo se encuentre.

**Capítulo 12: Smoke Test – Verificando que Todo Funciona (Corresponde al Paso 12 Práctico)**

Este paso es crucial para validar que todos los componentes que hemos configurado interactúan correctamente.

1.  **Encriptación de Datos (`Secrets`):**
    *   Al crear un `Secret` y luego inspeccionarlo directamente en `etcd` (usando `etcdctl` y `hexdump`), verificamos que el `kube-apiserver` está usando el `encryption-config.yaml` y que los datos sensibles realmente se almacenan cifrados. El prefijo `k8s:enc:aescbc:v1:key1:` en `etcd` lo confirma.
2.  **Deployments:**
    *   **¿Qué es un `Deployment`?** Es un objeto de Kubernetes que proporciona actualizaciones declarativas para Pods y ReplicaSets. Describes el estado deseado en un `Deployment`, y el controlador del `Deployment` cambia el estado actual al estado deseado a una velocidad controlada.
    *   Al crear un `Deployment` de `nginx`, le pedimos a Kubernetes que ejecute una o más instancias (Pods) de la imagen de `nginx`.
3.  **Pods:**
    *   **¿Qué es un `Pod`?** Es la unidad de computación más pequeña y simple que se puede crear y gestionar en Kubernetes. Un Pod representa una instancia de un proceso en ejecución en tu clúster. Puede contener uno o más contenedores (como contenedores Docker) que comparten recursos de almacenamiento y red, y una especificación sobre cómo ejecutar los contenedores.
4.  **Port Forwarding (`kubectl port-forward`):**
    *   Permite acceder a un puerto específico de un Pod desde tu máquina local (`jumpbox`). `kubectl` crea un túnel de red. Es útil para depuración y para acceder a aplicaciones que no están expuestas externamente a través de un `Service`.
5.  **Logs (`kubectl logs`):**
    *   Recupera los logs (salida estándar y error estándar) de los contenedores dentro de un Pod. Esencial para la depuración.
6.  **Exec (`kubectl exec`):**
    *   Permite ejecutar un comando directamente dentro de un contenedor en ejecución en un Pod. Útil para inspeccionar el entorno del contenedor o realizar tareas de diagnóstico.
7.  **Services:**
    *   **¿Qué es un `Service`?** Es una abstracción que define un conjunto lógico de Pods y una política para acceder a ellos. Los Servicios permiten un acoplamiento flexible entre los Pods que proporcionan una funcionalidad y los Pods que la consumen. Proporcionan una IP y un puerto estables (y un nombre DNS) para acceder a los Pods, incluso si las IPs de los Pods cambian (porque los Pods son efímeros).
    *   **`kubectl expose deployment nginx --type NodePort`:**
        *   `expose`: Crea un `Service` para un `Deployment` existente.
        *   `--type NodePort`: Este tipo de `Service` expone la aplicación en un puerto estático en la IP de cada nodo del clúster. El tráfico a `NodeIP:NodePort` se redirige al puerto del `Service` y luego a uno de los Pods que respaldan el `Service`.
        *   **Limitación en "The Hard Way":** No tenemos un proveedor de nube integrado, por lo que no podemos usar `type=LoadBalancer` automáticamente. `NodePort` es una forma sencilla de obtener acceso externo en este escenario.

**Capítulo 13: Limpieza – Deshaciendo el Camino (Corresponde al Paso 13 Práctico)**

*   Simplemente eliminar las máquinas virtuales es suficiente porque toda la configuración y los datos residen en ellas. No hay estado persistente fuera de las VMs en este tutorial.

---

**Parte IV: Mirando Hacia Adelante – Automatización y Próximos Pasos**

**Capítulo 14: Automatización – El Camino Inteligente a la Producción**

*   **¿Por qué automatizar después de "The Hard Way"?**
    Hacerlo manualmente es educativo, pero para entornos reales, es lento, propenso a errores y difícil de mantener y replicar.
*   **Herramientas de Automatización:**
    *   **Ansible:** Una herramienta de gestión de configuración, automatización de TI y despliegue de aplicaciones. Usarías playbooks de Ansible para ejecutar los mismos comandos y configuraciones que hicimos manualmente, pero de forma programática y repetible. El proyecto `kubernetes-hard-way-ansible` es un ejemplo directo.
    *   **Terraform:** Una herramienta de Infraestructura como Código (IaC). Se usa para provisionar y gestionar la infraestructura subyacente (VMs, redes, balanceadores de carga) en proveedores de nube o locales. Terraform definiría las 4 máquinas, sus redes, etc.
    *   **Combinación:** A menudo se usan juntas. Terraform crea la infraestructura, Ansible la configura.
*   **Otras herramientas de Instalación de Kubernetes:**
    *   **`kubeadm`:** Herramienta oficial de Kubernetes para simplificar la creación de clústeres. Automatiza muchos de los pasos que hicimos manualmente (generación de certificados, configuración de componentes del plano de control, unión de nodos).
    *   **k3s, RKE, kops, EKS, GKE, AKS:** Distribuciones ligeras, instaladores o servicios gestionados de Kubernetes que abstraen aún más la complejidad.

**Conclusión del Manual Teórico:**

Al completar "Kubernetes The Hard Way" y comprender la teoría detrás de cada paso, has ganado una visión invaluable del funcionamiento interno de Kubernetes. Esta base te permitirá:

*   **Depurar problemas con mayor eficacia:** Entiendes cómo interactúan los componentes.
*   **Tomar decisiones de diseño informadas:** Comprendes las implicaciones de diferentes configuraciones.
*   **Apreciar las herramientas de automatización:** Sabes el trabajo que te están ahorrando.
*   **Continuar aprendiendo con confianza:** Los conceptos más avanzados de Kubernetes se construirán sobre esta base sólida.
