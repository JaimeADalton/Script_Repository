def transformar_ip(ip):
    octetos = ip.split(".")
    binario = ""

    for octeto in octetos:
        binario += bin(int(octeto))[2:].zfill(8)

    decimal = int(binario, 2)
    return decimal

def transformar_decimal(decimal):
    binario = bin(decimal)[2:].zfill(32)  # Representación binaria de 32 bits

    octetos = [binario[i:i+8] for i in range(0, 32, 8)]
    direccion_ip = ".".join(str(int(octeto, 2)) for octeto in octetos)

    return direccion_ip

check=True
for numero in range(0,4294967295):
  direccion_ip=transformar_decimal(numero)
  decimal=transformar_ip(direccion_ip)
  if numero != decimal:
    print("Error:",direccion_ip,decimal)
  else:
    print("Correcto", decimal,direccion_ip)
