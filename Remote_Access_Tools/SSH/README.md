# SSH Tools

Conjunto de scripts y utilidades web para gestionar usuarios, claves y configuraciones SSH.

## Archivos

### `generador_url_share_keys.py`
- **Funcionalidad:** servidor HTTP seguro que genera URLs temporales para descargar pares de claves (`.key`, `.ppk`). Gestiona tokens con expiración, limpieza automática y permisos estrictos.
- **Precisión:** requiere Python 3 y dependencias estándar; opcionalmente se integra con `gestionar_usuarios.sh`. Ajustar `PORT` y `BASE_TEMP_DIR` según el entorno.
- **Complejidad:** alta.
- **Manual:** ejecutar `python3 generador_url_share_keys.py`, invocar `add_user_download()` desde otros scripts o adaptar para CLI.

### `gestionar_usuarios.sh`
- **Funcionalidad:** sincroniza cuentas locales basadas en `usernames.txt`, genera claves Ed25519, crea versiones PuTTY (`.ppk`) y soporta banderas `--force` para regenerar claves específicas.
- **Precisión:** exige ejecutar como root y depende de `puttygen` para los `.ppk` (si no está disponible, lo notifica). Protege usuarios de sistema.
- **Complejidad:** alta.
- **Manual:** `sudo ./gestionar_usuarios.sh [-f archivo] [--force usuario|--force-all] [-v]`.

### `sshconfig.sh`
- **Funcionalidad:** lista las entradas del fichero `~/.ssh/config` coloreadas para rápida referencia.
- **Precisión:** asume que el archivo existe; funciona tanto para root como para usuarios normales.
- **Complejidad:** baja.
- **Manual:** `./sshconfig.sh`.

### `sshconfig_edit.sh`
- **Funcionalidad:** asistente interactivo para añadir o eliminar hosts en `~/.ssh/config`, valida IPs, permite configurar `ProxyJump` y ofrece copiar claves con `ssh-copy-id`.
- **Precisión:** asume ruta estándar y claves almacenadas como `~/.ssh/access.key`. No incluye shebang; ejecutar con `bash sshconfig_edit.sh`.
- **Complejidad:** media.
- **Manual:** seguir los prompts para agregar (`a`) o eliminar (`r`) hosts.

### `sshdconfig_generator`
- **Funcionalidad:** generador interactivo de `sshd_config` con descripciones extensas y validaciones. Realiza copia de seguridad del archivo actual y crea `sshd_config.generated`.
- **Precisión:** requiere permisos de superusuario; guía al operador parámetro por parámetro.
- **Complejidad:** alta.
- **Manual:** `sudo ./sshdconfig_generator`, revisar el archivo generado y aplicarlo manualmente antes de reiniciar `sshd`.

### `User-Form.html`
- **Funcionalidad:** formulario web para recopilar datos de creación de usuarios, validando campos y generando JSON listo para automatizaciones.
- **Uso:** abrir en un navegador, completar el formulario y copiar el resultado generado.
