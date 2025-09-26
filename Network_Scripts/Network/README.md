# Network

### `interfaces_generator.sh`
- **Funcionalidad:** inspecciona interfaces físicas y VLAN existentes, calcula máscaras a partir de prefijos CIDR y genera `/etc/network/interfaces` para sistemas Debian.
- **Precisión:** utiliza comandos `ip` para detectar direcciones y rutas. Sobrescribe el archivo existente; realizar copia de seguridad antes de ejecutarlo.
- **Complejidad:** media.
- **Manual:** ejecutar como root (`sudo ./interfaces_generator.sh`) y verificar el resultado en `/etc/network/interfaces` antes de reiniciar la red.
