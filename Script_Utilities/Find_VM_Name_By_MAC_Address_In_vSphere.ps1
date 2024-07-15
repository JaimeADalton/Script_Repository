# Conectar al servidor vCenter (asegúrate de ajustar esto según tu entorno)
Connect-VIServer -Server "vcenter_ip"

try {
    while ($true) {
        # Solicitar la dirección MAC al usuario
        $macAddress = Read-Host "Introduce la dirección MAC (formato xx:xx:xx:xx:xx:xx) o 'q' para salir"

        # Salir del bucle si el usuario introduce 'q'
        if ($macAddress.ToLower() -eq 'q') {
            break
        }

        # Buscar la VM y obtener su nombre
        $vmName = Get-VM | Where-Object {$_.Guest.ExtensionData.Net.MacAddress -contains $macAddress} | Select-Object -ExpandProperty Name

        # Mostrar el resultado
        if ($vmName) {
            Write-Output "El nombre de la máquina virtual con la MAC $macAddress es: $vmName"
        } else {
            Write-Output "No se encontró ninguna máquina virtual con la MAC $macAddress"
        }

        Write-Output "" # Línea en blanco para separar las consultas
    }
}
finally {
    # Desconectar del servidor vCenter
    Disconnect-VIServer -Confirm:$false
    Write-Output "Sesión cerrada. Gracias por usar el script."
}
