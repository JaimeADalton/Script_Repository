# Windows

Scripts de automatización para sistemas Windows.

## Archivos
### `rdpsshtunel.ps1`
- **Funcionalidad:** crea un túnel SSH hacia un bastión, solicitando previamente la IP destino mediante una ventana gráfica (`System.Windows.Forms`). Tras comprobar que el puerto local está abierto, lanza `mstsc.exe` contra `localhost:<puerto>` y cierra el túnel al finalizar.
- **Precisión:** requiere OpenSSH cliente instalado, claves privadas accesibles y permisos para ejecutar procesos ocultos. Genera puertos aleatorios entre 30000-65535 y valida que el túnel esté activo con `Test-NetConnection`.
- **Complejidad:** media; combina GUI, procesos y limpieza automática.
- **Manual de uso:**
  1. Ajustar las variables `$bastionServer`, `$bastionUsername` y `$privateKeyPath`.
  2. Ejecutar el script en PowerShell con permisos adecuados (`Set-ExecutionPolicy` si es necesario).
  3. Introducir la IP del host RDP y esperar a que se abra la sesión de Escritorio Remoto.
