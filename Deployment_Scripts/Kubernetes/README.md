# Kubernetes

Recursos para automatizar la instalación de Kubernetes "The Hard Way".

## Archivos

### `kthw_autoinstall.sh`
- **Funcionalidad:** ejecuta todo el procedimiento "Kubernetes The Hard Way" sobre Debian 12: recopila parámetros, distribuye claves SSH, configura `/etc/hosts`, descarga binarios, genera certificados, instala control plane y workers, y aplica configuraciones de red.
- **Precisión:** requiere acceso root al jumpbox y a los nodos remotos, además de herramientas como `sshpass`, `curl`, `jq`. Las versiones de Kubernetes y dependencias están fijadas en el script.
- **Complejidad:** muy alta.
- **Manual de uso:**
  1. Ejecutar como root en la máquina de salto (`sudo ./kthw_autoinstall.sh`).
  2. Proporcionar dominio, IPs y credenciales cuando el script lo solicite.
  3. Verificar la salida final y utilizar `kubectl` desde el directorio generado.

### `The Hard Way Guide.md`
- **Funcionalidad:** guía escrita con el procedimiento detallado, útil para entender cada paso automatizado por el script.
