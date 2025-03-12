# Cheatsheet de Kubernetes en Linux: De Novato a Experto

## 🔰 NIVEL PRINCIPIANTE

### Instalación y Configuración

**Instalar kubectl en Linux**
```bash
# Descargar la última versión
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Hacer ejecutable el binario
chmod +x kubectl

# Mover kubectl al PATH
sudo mv kubectl /usr/local/bin/
```

**Instalar Minikube (entorno local)**
```bash
# Instalar minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Iniciar clúster
minikube start
```

**Comprobar instalación**
```bash
kubectl version --client
minikube status
```

### Comandos Básicos

**Obtener información del clúster**
```bash
# Ver nodos del clúster
kubectl get nodes

# Ver todos los objetos en todos los namespaces
kubectl get all --all-namespaces
```

**Crear recursos**
```bash
# Crear un deployment
kubectl create deployment mi-nginx --image=nginx

# Crear un servicio
kubectl expose deployment mi-nginx --port=80 --type=NodePort
```

**Gestionar Pods**
```bash
# Listar pods
kubectl get pods

# Describir un pod
kubectl describe pod <nombre-pod>

# Ejecutar bash en un pod
kubectl exec -it <nombre-pod> -- /bin/bash

# Ver logs de un pod
kubectl logs <nombre-pod>
```

**Trabajar con archivos YAML**
```bash
# Aplicar configuración desde archivo YAML
kubectl apply -f mi-deployment.yaml

# Crear archivo YAML sin aplicar
kubectl create deployment mi-app --image=nginx --dry-run=client -o yaml > deployment.yaml
```

## 🔄 NIVEL INTERMEDIO

### Gestión de Recursos

**Namespaces**
```bash
# Crear namespace
kubectl create namespace mi-namespace

# Listar recursos en un namespace
kubectl get all -n mi-namespace

# Establecer namespace por defecto
kubectl config set-context --current --namespace=mi-namespace
```

**Deployments**
```bash
# Escalar deployment
kubectl scale deployment mi-app --replicas=5

# Actualizar imagen
kubectl set image deployment/mi-app mi-app=nginx:latest

# Ver historial de rollouts
kubectl rollout history deployment/mi-app

# Deshacer último rollout
kubectl rollout undo deployment/mi-app
```

**ConfigMaps y Secrets**
```bash
# Crear ConfigMap
kubectl create configmap app-config --from-file=config.properties

# Crear Secret
kubectl create secret generic app-secret --from-literal=DB_PASSWORD=password123

# Obtener valor de un ConfigMap
kubectl get configmap app-config -o jsonpath='{.data.config\.properties}'
```

### Redes

**Services**
```bash
# Tipos de servicios
kubectl create service clusterip mi-servicio --tcp=80:80
kubectl create service nodeport mi-servicio --tcp=80:80
kubectl create service loadbalancer mi-servicio --tcp=80:80

# Port-forwarding
kubectl port-forward service/mi-servicio 8080:80
```

**Ingress**
```bash
# Habilitar complemento ingress en minikube
minikube addons enable ingress

# Crear ingress
kubectl apply -f mi-ingress.yaml
```

### Almacenamiento

**Persistent Volumes**
```bash
# Crear PersistentVolumeClaim
kubectl apply -f mi-pvc.yaml

# Listar PersistentVolumes y PVCs
kubectl get pv,pvc
```

## 🚀 NIVEL AVANZADO

### Gestión Avanzada de Aplicaciones

**StatefulSets**
```bash
# Crear StatefulSet
kubectl apply -f mi-statefulset.yaml

# Escalar StatefulSet
kubectl scale statefulset mi-statefulset --replicas=5
```

**DaemonSets**
```bash
# Crear DaemonSet
kubectl apply -f mi-daemonset.yaml

# Ver DaemonSets
kubectl get daemonsets
```

**Jobs y CronJobs**
```bash
# Crear Job
kubectl create job mi-job --image=busybox -- echo "Trabajo completado"

# Crear CronJob
kubectl create cronjob mi-cronjob --image=busybox --schedule="*/5 * * * *" -- echo "Ejecutado cada 5 minutos"
```

### RBAC (Control de Acceso Basado en Roles)

```bash
# Crear rol
kubectl create role mi-rol --verb=get,list,watch --resource=pods,services

# Crear RoleBinding
kubectl create rolebinding mi-binding --role=mi-rol --user=mi-usuario

# Verificar permisos
kubectl auth can-i list pods --as=mi-usuario
```

### Monitorización y Troubleshooting

```bash
# Top de pods (uso de recursos)
kubectl top pods

# Eventos del clúster
kubectl get events --sort-by=.metadata.creationTimestamp

# Describir nodo
kubectl describe node <nombre-nodo>

# Verificar componentes del clúster
kubectl get componentstatuses
```

### Helm (Gestor de Paquetes)

```bash
# Instalar Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Añadir repositorio
helm repo add bitnami https://charts.bitnami.com/bitnami

# Buscar charts
helm search repo bitnami

# Instalar chart
helm install mi-release bitnami/nginx
```

## 🧠 NIVEL EXPERTO

### Alta Disponibilidad y Producción

**Cluster Autoscaling**
```bash
# Habilitar autoscaling en GKE
gcloud container clusters update mi-cluster --enable-autoscaling --min-nodes=3 --max-nodes=10

# En AWS EKS
eksctl scale nodegroup --cluster=mi-cluster --name=workers --nodes-min=3 --nodes-max=10
```

**Horizontal Pod Autoscaler**
```bash
# Crear HPA
kubectl autoscale deployment mi-app --cpu-percent=80 --min=1 --max=10

# Ver HPA
kubectl get hpa
```

**Network Policies**
```bash
# Aplicar política de red
kubectl apply -f mi-network-policy.yaml
```

### CI/CD e Infraestructura como Código

**Integración con ArgoCD**
```bash
# Instalar ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Acceder a UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**Kustomize**
```bash
# Estructura base
kustomize build ./base

# Aplicar overlay
kustomize build ./overlays/production | kubectl apply -f -
```

### Custom Resources y Operadores

```bash
# Definir CRD
kubectl apply -f mi-custom-resource-definition.yaml

# Instalar operador
kubectl apply -f https://example.com/operators/my-operator.yaml
```

### Servicios de Malla (Service Mesh)

**Istio**
```bash
# Instalar Istio
istioctl install --set profile=demo

# Habilitar inyección automática
kubectl label namespace default istio-injection=enabled
```

## 📚 HERRAMIENTAS AVANZADAS Y MEJORES PRÁCTICAS

### Herramientas para desarrolladores

```bash
# k9s - TUI para Kubernetes
curl -sS https://webinstall.dev/k9s | bash

# Kubecfg - Gestionar multiples clusters
kubectx minikube  # Cambiar al contexto minikube
kubens kube-system  # Cambiar al namespace kube-system
```

### Seguridad y auditoría

```bash
# Kube-bench (verificación CIS)
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-aks.yaml

# Trivy (escaneo de vulnerabilidades)
trivy image nginx:latest
```

### Backup y Recuperación

```bash
# Velero
velero backup create mi-backup --include-namespaces=default
velero restore create --from-backup mi-backup
```

### Gitops

```bash
# Flux CD
flux bootstrap github \
  --owner=mi-usuario \
  --repository=mi-gitops-repo \
  --path=clusters/mi-cluster
```

## 🤖 CONSEJOS PARA MAESTROS KUBERNETES

1. **Automatiza todo**: Usa Infrastructure as Code (Terraform, Pulumi) para automatizar la creación de clústeres
2. **Adopta GitOps**: Todas las configuraciones deben estar en Git y sincronizarse automáticamente
3. **Usa Canary Deployments**: Implementa progresivamente cambios para reducir riesgos
4. **Prioriza la Observabilidad**: Prometheus, Grafana, OpenTelemetry para monitorización completa
5. **Implementa Zero-Trust Security**: NetworkPolicies restrictivas, RBAC estricto, OPA/Gatekeeper para validación
6. **Domina FinOps para K8s**: Optimiza costos con namespace resource quotas, límites de recursos y Kubernetes cost allocation tools
7. **Profundiza en el troubleshooting avanzado**: Domina la depuración a nivel de componentes y la inspección detallada del clúster

---

## 📝 ARCHIVOS YAML ESENCIALES

### Ejemplo de Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
```

### Ejemplo de Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

### Ejemplo de Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minimal-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
```

### Ejemplo de PersistentVolumeClaim
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: standard
```

---

## 💡 GLOSARIO DE TÉRMINOS

- **Pod**: Unidad más pequeña en Kubernetes, contiene uno o más contenedores
- **Node**: Máquina física o virtual en el clúster
- **Control Plane**: Componentes que gestionan el clúster (API Server, Scheduler, etc.)
- **Namespace**: Forma de dividir los recursos del clúster en grupos lógicos
- **Service**: Abstracción para exponer aplicaciones en la red
- **Ingress**: Gestiona el acceso externo a los servicios
- **ConfigMap**: Almacena datos de configuración no confidenciales
- **Secret**: Almacena datos confidenciales como contraseñas
- **StatefulSet**: Para aplicaciones con estado
- **DaemonSet**: Asegura que todos o algunos nodos ejecuten una copia de un pod
- **HPA**: Horizontal Pod Autoscaler, escala automáticamente pods según uso
- **PV/PVC**: Persistent Volume / Persistent Volume Claim, gestión de almacenamiento
