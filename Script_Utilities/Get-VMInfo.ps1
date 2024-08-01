# Conectar al servidor vCenter (asegúrate de ajustar esto según tu entorno)
try {
    Connect-VIServer -Server "Change_Me_To_FQDN" -ErrorAction Stop
}
catch {
    Write-Error "No se pudo conectar al servidor vCenter: $_"
    exit
}

function Get-DetailedVMInfo {
    param($vm)
    return [PSCustomObject]@{
        "Nombre" = $vm.Name
        "RAM (GB)" = [math]::Round($vm.MemoryGB, 2)
        "CPU" = $vm.NumCpu
        "Estado" = $vm.PowerState
        "Espacio en disco (GB)" = [math]::Round(($vm.UsedSpaceGB), 2)
        "MAC Address" = ($vm.Guest.ExtensionData.Net | ForEach-Object { $_.MacAddress }) -join ", "
        "IP Address" = ($vm.Guest.ExtensionData.Net | ForEach-Object { $_.IpAddress }) -join ", "
        "Host" = $vm.VMHost.Name
        "Datastore" = ($vm.DatastoreIdList | ForEach-Object { (Get-Datastore -Id $_).Name }) -join ", "
        "Snapshots" = ($vm | Get-Snapshot | Measure-Object).Count
    }
}

try {
    while ($true) {
        $searchType = Read-Host "¿Deseas buscar por MAC, IP o nombre de VM? (Escribe 'MAC', 'IP', 'NAME' o 'q' para salir)"
        if ($searchType.ToLower() -eq 'q') {
            break
        }
        if ($searchType.ToUpper() -eq 'MAC') {
            $macAddress = Read-Host "Introduce la dirección MAC (completa o parcial)"
            $vms = Get-VM | Where-Object {
                $_.Guest.ExtensionData.Net.MacAddress | Where-Object { $_ -like "*$macAddress*" }
            }
        }
        elseif ($searchType.ToUpper() -eq 'IP') {
            $ipAddress = Read-Host "Introduce la dirección IP (completa o parcial)"
            $vms = Get-VM | Where-Object {
                $_.Guest.ExtensionData.Net.IpAddress | Where-Object { $_ -like "*$ipAddress*" }
            }
        }
        elseif ($searchType.ToUpper() -eq 'NAME') {
            $vmName = Read-Host "Introduce el nombre (completo o parcial) de la máquina virtual"
            $vms = Get-VM -Name "*$vmName*"
        }
        else {
            Write-Output "Opción no válida. Por favor, escribe 'MAC', 'IP', 'NAME' o 'q' para salir."
            continue
        }

        if ($vms) {
            foreach ($vm in $vms) {
                $vmInfo = Get-DetailedVMInfo $vm
                $vmInfo | Format-List
            }
        } else {
            Write-Output "No se encontró ninguna máquina virtual con los criterios especificados."
        }
        Write-Output "" # Línea en blanco para separar las consultas
    }
}
catch {
    Write-Error "Se produjo un error durante la ejecución del script: $_"
}
finally {
    try {
        Disconnect-VIServer -Confirm:$false
        Write-Output "Sesión cerrada. Gracias por usar el script."
    }
    catch {
        Write-Error "Error al desconectar del servidor vCenter: $_"
    }
}
