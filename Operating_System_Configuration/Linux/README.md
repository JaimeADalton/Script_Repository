# Linux

Scripts y configuraciones para automatizar tareas comunes en sistemas Linux.

## Scripts

### `user_management.sh`
- **Funcionalidad:** sincroniza los usuarios locales con una lista `usernames.txt`: crea cuentas que faltan, genera claves SSH y elimina las que no estén listadas (con excepciones predefinidas).
- **Precisión:** depende de la presencia de `usernames.txt` en el directorio de trabajo y de utilidades como `useradd`, `ssh-keygen` y `userdel`. La lista de excepciones debe mantenerse actualizada para evitar eliminar cuentas de sistema.
- **Complejidad:** media.
- **Manual de uso:**
  1. Preparar `usernames.txt` con un usuario por línea.
  2. Ejecutar como root (`sudo ./user_management.sh`).
  3. Revisar `/var/log/auth.log` o el propio output para validar la creación/eliminación de cuentas.

## Subdirectorios

### `Kali`
- **Archivos:** `.zshrc` y `.zsh_functions` personalizados para entornos Kali Linux.
- **Uso:** copiar a `$HOME` del usuario objetivo para aplicar alias y funciones preconfiguradas.

### `OpenLDAP`
- **Archivo:** `openldap_configure_wizard.sh`.
  - **Funcionalidad:** asistente interactivo que genera ficheros `usuario.ldif`, `grupos.ldif` y `unidadesorganizativas.ldif` en `$HOME/LDAP`.
  - **Manual de uso:** ejecutar el script, indicar la cantidad de objetos a crear y responder a los prompts. Importar los `.ldif` resultantes con `ldapadd`.

### `Update_RHEL8.0`
- **Archivo:** `Actualizar_RHEL8.0`.
  - **Funcionalidad:** registra un sistema RHEL 8.6 con `subscription-manager`, limpia cachés `yum`, ejecuta `yum update -y` y reinicia.
  - **Manual de uso:** editar `username` y `password`, ejecutar como root y monitorizar `/var/log/script.log` para validar el proceso.
