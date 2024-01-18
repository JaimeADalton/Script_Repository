import sys

def dividir_archivo_en_bloques(nombre_archivo, tamano_bloque):
    try:
        tamano_bloque = int(tamano_bloque)
    except ValueError:
        print("El tamaño del bloque debe ser un número entero.")
        return

    with open(nombre_archivo, 'r', encoding='utf-8') as archivo:
        contenido = archivo.read()

    bloques = [contenido[i:i + tamano_bloque] for i in range(0, len(contenido), tamano_bloque)]

    for indice, bloque in enumerate(bloques):
        with open(f"{nombre_archivo}_bloque_{indice + 1}.txt", 'w', encoding='utf-8') as archivo_salida:
            archivo_salida.write(bloque)

    print(f"Archivo dividido en {len(bloques)} bloques.")

def mostrar_manual():
    manual = """Uso: python splitxt.py [NOMBRE_ARCHIVO] [TAMAÑO_BLOQUE]

Divide un archivo en varios bloques de un tamaño especificado.

Argumentos:
    NOMBRE_ARCHIVO: Ruta al archivo que se desea dividir.
    TAMAÑO_BLOQUE: Tamaño de cada bloque en bytes.

Ejemplo:
    python splitxt.py mi_archivo.txt 40000
"""
    print(manual)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        mostrar_manual()
        sys.exit()

    nombre_archivo = sys.argv[1]
    tamano_bloque = sys.argv[2]
    dividir_archivo_en_bloques(nombre_archivo, tamano_bloque)
