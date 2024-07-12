Para utilizar el script **AsyncNmapScanner**, necesitas proporcionarle al menos un archivo de entrada que contenga las direcciones IP a escanear. Aquí tienes un ejemplo detallado de cómo usar el script desde la línea de comandos:

### Comando Básico
```bash
python AsyncNmapScanner.py -i path/to/your/ip_list.txt
```

### Parámetros Opcionales
- `-o OUTPUT`: Especifica un archivo de salida para guardar los resultados en formato JSON.
- `-p PORT_RANGE`: Define el rango de puertos a escanear (por defecto es `1-65535`).
- `-a SCAN_ARGS`: Configura los argumentos de escaneo de Nmap (por defecto es `-T5 -n -Pn --min-rate=5000 --max-retries=2`).
- `-m MAX_CONCURRENT`: Establece el número máximo de escaneos concurrentes (por defecto es `1000`).
- `-u`: Realiza un escaneo UDP además del escaneo TCP.

### Ejemplos de Uso

1. **Escaneo Básico**: Escaneo de una lista de IPs con configuración por defecto.
    ```bash
    python AsyncNmapScanner.py -i ip_list.txt
    ```

2. **Guardar Resultados en un Archivo**: Escaneo de IPs y guardar los resultados en `results.json`.
    ```bash
    python AsyncNmapScanner.py -i ip_list.txt -o results.json
    ```

3. **Escaneo de Rango de Puertos Específico**: Escanear solo los puertos del 80 al 100.
    ```bash
    python AsyncNmapScanner.py -i ip_list.txt -p 80-100
    ```

4. **Escaneo con Argumentos Personalizados**: Usar argumentos de escaneo personalizados para Nmap.
    ```bash
    python AsyncNmapScanner.py -i ip_list.txt -a "-T4 -n -Pn --min-rate=3000"
    ```

5. **Escaneo UDP Adicional**: Incluir un escaneo UDP además del escaneo TCP.
    ```bash
    python AsyncNmapScanner.py -i ip_list.txt -u
    ```

6. **Controlar la Concurrencia**: Limitar el número de escaneos concurrentes a 500.
    ```bash
    python AsyncNmapScanner.py -i ip_list.txt -m 500
    ```

### Uso Completo con Todos los Parámetros
```bash
python AsyncNmapScanner.py -i ip_list.txt -o results.json -p 1-1024 -a "-T4 -n -Pn" -m 500 -u
```

### Mensaje de Ayuda
Si necesitas ver todas las opciones disponibles, puedes usar la opción `-h` o `--help`:
```bash
python AsyncNmapScanner.py -h
```

Esto mostrará una ayuda detallada con la descripción de cada parámetro.
