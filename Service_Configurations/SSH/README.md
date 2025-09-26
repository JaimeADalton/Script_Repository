# SSH

Ejemplo completo de `sshd_config` con la mayoría de las directivas disponibles comentadas.

- **Funcionalidad:** sirve como referencia para endurecer o habilitar características de OpenSSH. Incluye ejemplos de `AcceptEnv`, listas de usuarios/grupos permitidos o denegados, banners, opciones de GSSAPI, CAs, algoritmos y controles de forwarding.
- **Precisión:** los valores responden a la sintaxis oficial de OpenSSH 8.x. No se aplican validaciones automáticas; al copiarlo conviene revisar que las rutas (por ejemplo `/usr/local/sbin/lookup-ssh-keys`) existan en el sistema.
- **Complejidad:** baja-media; es un fichero declarativo extenso sin lógica, pero cubre ajustes avanzados.
- **Manual de uso:**
  1. Copiar el archivo a `/etc/ssh/sshd_config` o integrarlo parcialmente.
  2. Sustituir usuarios, grupos, rutas y algoritmos según la política interna.
  3. Ejecutar `sshd -t` para validar la sintaxis y reiniciar el servicio (`systemctl restart sshd`).
