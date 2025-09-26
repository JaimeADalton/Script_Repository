# OpenLDAP

Asistente para generar entradas LDIF.

## Script
### `openldap_configure_wizard.sh`
- **Funcionalidad:** crea archivos `usuario.ldif`, `grupos.ldif` y `unidadesorganizativas.ldif` pidiendo datos por consola y aplicando hashing de contraseñas mediante `slappasswd`.
- **Precisión:** asume que `slappasswd` está disponible y que los DN siguen el formato `dc=ejemplo,dc=com`. Separa el dominio en dos componentes (`dc1`, `dc2`).
- **Complejidad:** media; combina menús, bucles y cat heredocs.
- **Manual de uso:** ejecutar el script, elegir la acción y proporcionar los parámetros solicitados. Los archivos se guardan en `$HOME/LDAP` listos para importarse con `ldapadd -x -D "cn=admin,dc=..." -W -f archivo.ldif`.
