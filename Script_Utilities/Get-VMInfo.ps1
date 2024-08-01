# Conectar al servidor vCenter (asegúrate de ajustar esto según tu entorno)
Connect-VIServer -Server "Change_Me_To_FQDN"

try {
    while ($true) {
        # Solicitar al usuario que elija entre buscar por MAC o IP
        $searchType = Read-Host "¿Deseas buscar por MAC o IP? (Escribe 'MAC', 'IP' o 'q' para salir)"

        # Salir del bucle si el usuario introduce 'q'
        if ($searchType.ToLower() -eq 'q') {
            break
        }

        if ($searchType.ToUpper() -eq 'MAC') {
            # Buscar por dirección MAC
            $macAddress = Read-Host "Introduce la dirección MAC (formato xx:xx:xx:xx:xx:xx)"
            $vmName = Get-VM | Where-Object {$_.Guest.ExtensionData.Net.MacAddress -contains $macAddress} | Select-Object -ExpandProperty Name

            if ($vmName) {
                Write-Output "El nombre de la máquina virtual con la MAC $macAddress es: $vmName"
            } else {
                Write-Output "No se encontró ninguna máquina virtual con la MAC $macAddress"
            }
        }
        elseif ($searchType.ToUpper() -eq 'IP') {
            # Buscar por dirección IP
            $ipAddress = Read-Host "Introduce la dirección IP"
            $vms = Get-VM | Where-Object {
                $_.Guest.IPAddress -ne $null -and ($_.Guest.IPAddress | Where-Object { $_ -eq $ipAddress })
            }

            if ($vms) {
                foreach ($vm in $vms) {
                    Write-Output "El nombre de la máquina virtual con la IP $ipAddress es: $($vm.Name)"
                    Write-Output "IPs asociadas: $($vm.Guest.IPAddress -join ', ')"
                }
            } else {
                Write-Output "No se encontró ninguna máquina virtual con la IP $ipAddress"
            }
        }
        else {
            Write-Output "Opción no válida. Por favor, escribe 'MAC', 'IP' o 'q' para salir."
        }

        Write-Output "" # Línea en blanco para separar las consultas
    }
}
finally {
    # Desconectar del servidor vCenter
    Disconnect-VIServer -Confirm:$false
    Write-Output "Sesión cerrada. Gracias por usar el script."
}
