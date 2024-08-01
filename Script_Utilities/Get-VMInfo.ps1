# Definir el usuario fijo para vCenter
$vCenterUser = "Change_Me_To_Username"
$vCenterServer = "Change_Me_To_FQDN"

# Solicitar la contraseña al usuario y crear un objeto de credencial
$vCenterPassword = Read-Host "Introduce la contraseña para $vCenterUser" -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential($vCenterUser, $vCenterPassword)

# Conectar al servidor vCenter
try {
    Connect-VIServer -Server $vCenterServer -Credential $credential -ErrorAction Stop
    Write-Output "Conexión exitosa a vCenter como $vCenterUser"
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

function Remove-LeadingTrailingSpaces {
    param([string]$inputString)
    return $inputString.Trim()
}

try {
    while ($true) {
        $searchType = Remove-LeadingTrailingSpaces (Read-Host "¿Deseas buscar por MAC, IP o nombre de VM? (Escribe 'MAC', 'IP', 'NAME' o 'q' para salir)")
        if ($searchType.ToLower() -eq 'q') {
            break
        }
        if ($searchType.ToUpper() -eq 'MAC') {
            $macAddress = Remove-LeadingTrailingSpaces (Read-Host "Introduce la dirección MAC (completa o parcial)")
            $vms = Get-VM | Where-Object {
                $_.Guest.ExtensionData.Net.MacAddress | Where-Object { $_ -like "*$macAddress*" }
            }
        }
        elseif ($searchType.ToUpper() -eq 'IP') {
            $ipAddress = Remove-LeadingTrailingSpaces (Read-Host "Introduce la dirección IP (completa o parcial)")
            $vms = Get-VM | Where-Object {
                $_.Guest.ExtensionData.Net.IpAddress | Where-Object { $_ -like "*$ipAddress*" }
            }
        }
        elseif ($searchType.ToUpper() -eq 'NAME') {
            $vmName = Remove-LeadingTrailingSpaces (Read-Host "Introduce el nombre (completo o parcial) de la máquina virtual")
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
