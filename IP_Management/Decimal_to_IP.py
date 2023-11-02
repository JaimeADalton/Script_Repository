def transformar_decimal(decimal):
    binario = bin(decimal)[2:].zfill(32)  # Representación binaria de 32 bits

    octetos = [binario[i:i+8] for i in range(0, 32, 8)]
    direccion_ip = ".".join(str(int(octeto, 2)) for octeto in octetos)

    return direccion_ip
