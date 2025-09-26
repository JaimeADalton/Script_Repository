# PHP Web Monitor SNMP

- **`index.php`**
  - **Funcionalidad:** carga las definiciones de host de Nagios, ejecuta pings en paralelo y muestra estado/latencia desde una interfaz web con refresco dinámico (via AJAX).
  - **Requisitos:** PHP con acceso a funciones `proc_open`, permisos para leer `/usr/local/nagios/etc/objects` y ejecutar `ping`.
  - **Manual:** desplegar en un servidor web (por ejemplo, `/usr/local/nagios/share/`), asegurarse de que PHP tenga permisos adecuados y acceder mediante navegador para visualizar el estado de los hosts.
