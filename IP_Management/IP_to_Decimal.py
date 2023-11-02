def transformar_ip(ip):
    octetos = ip.split(".")
    binario = ""

    for octeto in octetos:
        binario += bin(int(octeto))[2:].zfill(8)

    decimal = int(binario, 2)
    return decimal
