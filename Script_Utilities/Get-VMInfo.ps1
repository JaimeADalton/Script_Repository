# Definir el usuario fijo para vCenter
$vCenterUser = "Change_Me_To_Username"
$vCenterServer = "Change_Me_To_FQDN"

# Solicitar la contraseña al usuario y crear un objeto de credencial
$vCenterPassword = Read-Host "Introduce la contraseña para $vCenterUser" -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential($vCenterUser, $vCenterPassword)
#$DebugPreference = "SilentlyContinue"

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

$GetInputTypeScriptBlock = {
    param($input)

    if ([string]::IsNullOrEmpty($input)) {
        return 'UNKNOWN'
    }

    $input = $input.Trim()

    if ($input -match '^(\d{1,3}\.){3}\d{1,3}$') {
        $octets = $input.Split('.')
        if ($octets.Count -eq 4 -and $octets | ForEach-Object { [int]$_ -ge 0 -and [int]$_ -le 255 }) {
            return 'IP Completa'
        }
    }

    if ($input -match '^(\d{1,3}\.){0,2}\d{1,3}$') {
        $octets = $input.Split('.')
        if ($octets | ForEach-Object { $_ -match '^\d{1,3}$' -and [int]$_ -ge 0 -and [int]$_ -le 255 }) {
            return 'IP Parcial'
        }
    }

    if ($input -match '^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$') {
        return 'MAC Completa'
    }

    if ($input -match '^([0-9A-Fa-f]{1,2}[:-]){0,5}[0-9A-Fa-f]{1,2}$') {
        return 'MAC Parcial'
    }

    if ($input -match '^[a-zA-Z0-9\-_\.]+$') {
        return 'NAME'
    }

    return 'UNKNOWN'
}

try {
    while ($true) {
        $searchInput = Remove-LeadingTrailingSpaces (Read-Host "Introduce IP, MAC o nombre de VM (o 'q' para salir)")
        if ($searchInput.ToLower() -eq 'q') {
            break
        }

        $searchType = Invoke-Command -ScriptBlock $GetInputTypeScriptBlock -ArgumentList $searchInput

        $vms = @()
        switch ($searchType) {
            'IP Completa' {
                $vms = Get-VM | Where-Object {
                    $_.Guest.IPAddress -contains $searchInput
                }
            }
            'IP Parcial' {
                $vms = Get-VM | Where-Object {
                    $_.Guest.IPAddress | Where-Object { $_ -like "*$searchInput*" }
                }
            }
            'MAC Completa' {
                $vms = Get-VM | Where-Object {
                    $_.ExtensionData.Config.Hardware.Device | 
                    Where-Object { $_ -is [VMware.Vim.VirtualEthernetCard] } |
                    Where-Object { $_.MacAddress -eq $searchInput }
                }
            }
            'MAC Parcial' {
                $vms = Get-VM | Where-Object {
                    $_.ExtensionData.Config.Hardware.Device | 
                    Where-Object { $_ -is [VMware.Vim.VirtualEthernetCard] } |
                    Where-Object { $_.MacAddress -like "*$searchInput*" }
                }
            }
            'NAME' {
                $vms = Get-VM -Name "*$searchInput*"
            }
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


