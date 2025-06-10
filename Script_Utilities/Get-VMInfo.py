#!/usr/bin/pwsh
param(
    [switch]$AllData
)

# Definir el usuario fijo para vCenter
$vCenterUser = "Change_Me_To_Username"
$vCenterServer = "Change_Me_To_FQDN"

# Solicitar la contraseña al usuario y crear un objeto de credencial
$vCenterPassword = Read-Host "Introduce la contraseña para $vCenterUser" -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential($vCenterUser, $vCenterPassword)
$DebugPreference = "SilentlyContinue"

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
    param(
        [Parameter(Mandatory=$true)]
        $vm,
        [switch]$AllData
    )
    
    # Información básica (siempre se muestra)
    $info = [PSCustomObject]@{
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
    
    # Obtener información de red y VLAN mejorada
    $vlanInfo = @()
    
    # Obtener los adaptadores de red de la VM
    $networkAdapters = Get-NetworkAdapter -VM $vm
    
    foreach ($adapter in $networkAdapters) {
        $networkName = $adapter.NetworkName
        if ($networkName) {
            # Intentar obtener información de VLAN del portgroup
            $vlanId = $null
            
            # Primero intentar como portgroup estándar
            try {
                $pg = Get-VirtualPortGroup -Name $networkName -VMHost $vm.VMHost -Standard -ErrorAction SilentlyContinue
                if ($pg) {
                    $vlanId = $pg.VlanId
                }
            }
            catch { }
            
            # Si no se encontró, intentar como portgroup distribuido
            if (-not $vlanId) {
                try {
                    $dpg = Get-VDPortgroup -Name $networkName -ErrorAction SilentlyContinue
                    if ($dpg) {
                        $vlanConfig = $dpg.ExtensionData.Config.DefaultPortConfig.Vlan
                        if ($vlanConfig -and $vlanConfig.VlanId) {
                            $vlanId = $vlanConfig.VlanId
                        }
                    }
                }
                catch { }
            }
            
            if ($vlanId) {
                $vlanInfo += "$networkName (VLAN $vlanId)"
            }
            else {
                $vlanInfo += $networkName
            }
        }
    }
    
    $info | Add-Member -NotePropertyName "Network/VLAN" -NotePropertyValue ($vlanInfo -join ", ")
    
    # Si se solicita toda la información adicional
    if ($AllData) {
        # Obtén datos de los adaptadores de red
        $vmNetworkAdapters = $vm.ExtensionData.Config.Hardware.Device | Where-Object { $_ -is [VMware.Vim.VirtualEthernetCard] }
        
        # Obtener la carpeta de la VM
        $folder = $vm.Folder.Name
        
        # Información adicional
        $additionalInfo = @{
            "Sistema Operativo" = $vm.Guest.OSFullName
            "Folder" = $folder
            "Versión VMWare Tools" = $vm.ExtensionData.Guest.ToolsVersion
            "Versión Hardware" = $vm.HardwareVersion
            "Tipo de Tarjeta" = ($vmNetworkAdapters | ForEach-Object { $_.GetType().Name }) -join ", "
            "Tipo Adaptador" = ($networkAdapters | ForEach-Object { $_.Type }) -join ", "
            "Conectado" = ($networkAdapters | ForEach-Object { $_.ConnectionState.Connected }) -join ", "
            "Asignación IP" = ($vm.Guest.ExtensionData.Net | ForEach-Object {
                if ($_.IpConfig -and $_.IpConfig.IpAddress) {
                    $_.IpConfig.IpAddress | ForEach-Object { $_.Origin }
                }
            }) -join ", "
        }
        
        # Agregar propiedades adicionales al objeto
        foreach ($key in $additionalInfo.Keys) {
            $info | Add-Member -NotePropertyName $key -NotePropertyValue $additionalInfo[$key]
        }
    }
    
    return $info
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

    # Verificar si es IP completa
    if ($input -match '^(\d{1,3}\.){3}\d{1,3}$') {
        $octets = $input.Split('.')
        if ($octets.Count -eq 4 -and $octets | ForEach-Object { [int]$_ -ge 0 -and [int]$_ -le 255 }) {
            return 'IP Completa'
        }
    }

    # Verificar si es IP parcial
    if ($input -match '^(\d{1,3}\.){0,2}\d{1,3}$') {
        $octets = $input.Split('.')
        if ($octets | ForEach-Object { $_ -match '^\d{1,3}$' -and [int]$_ -ge 0 -and [int]$_ -le 255 }) {
            return 'IP Parcial'
        }
    }

    # Verificar si es MAC completa
    if ($input -match '^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$') {
        return 'MAC Completa'
    }

    # Verificar si es MAC parcial
    if ($input -match '^([0-9A-Fa-f]{1,2}[:-]){0,5}[0-9A-Fa-f]{1,2}$') {
        return 'MAC Parcial'
    }

    # Verificar si es VLAN (varios formatos)
    if ($input -match '(?i)^vlan\s*\d+$' -or $input -match '^\d+$') {
        # Si es solo un número, verificar que sea un ID de VLAN válido (1-4094)
        if ($input -match '^\d+$') {
            $vlanId = [int]$input
            if ($vlanId -ge 1 -and $vlanId -le 4094) {
                return 'VLAN'
            }
        }
        else {
            return 'VLAN'
        }
    }

    # Verificar si es un Datastore existente
    if (Get-Datastore -Name $input -ErrorAction SilentlyContinue) {
        return 'DATASTORE'
    }

    # Si contiene caracteres alfanuméricos válidos, es un nombre
    if ($input -match '^[a-zA-Z0-9\-_\.\s]+$') {
        return 'NAME'
    }

    return 'UNKNOWN'
}

# Mostrar opciones disponibles al inicio
Write-Output "`n=== Script de búsqueda de VMs en vCenter ==="
Write-Output "Opciones de búsqueda disponibles:"
Write-Output "  - IP completa (ej: 192.168.1.10)"
Write-Output "  - IP parcial (ej: 192.168)"
Write-Output "  - MAC completa (ej: 00:50:56:91:5c:6d)"
Write-Output "  - MAC parcial (ej: 00:50)"
Write-Output "  - Nombre de VM (ej: servidor01)"
Write-Output "  - Nombre de Portgroup (ej: VLAN_INSIDE_PIX)"
Write-Output "  - Datastore (ej: DS01)"
Write-Output "  - VLAN ID (ej: 199 o vlan 199)"
Write-Output "  - 'q' para salir"

if ($AllData) {
    Write-Output "`n[Modo información extendida ACTIVADO]"
} else {
    Write-Output "`nTip: Ejecuta el script con -AllData para ver información extendida de las VMs"
}
Write-Output ""

try {
    while ($true) {
        $searchInput = Remove-LeadingTrailingSpaces (Read-Host "Introduce tu búsqueda")
        if ($searchInput.ToLower() -eq 'q') {
            break
        }

        $searchType = Invoke-Command -ScriptBlock $GetInputTypeScriptBlock -ArgumentList $searchInput
        Write-Output "Tipo de búsqueda detectado: $searchType"

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
                # Primero buscar como nombre de VM
                $vms = Get-VM -Name "*$searchInput*" -ErrorAction SilentlyContinue
                
                # Si no se encuentran VMs, buscar como nombre de portgroup
                if (-not $vms) {
                    Write-Output "No se encontró VM con ese nombre. Buscando como portgroup..."
                    
                    # Buscar todas las VMs que usen ese portgroup
                    $allVMs = Get-VM
                    $vms = @()
                    
                    foreach ($vm in $allVMs) {
                        $adapters = Get-NetworkAdapter -VM $vm
                        foreach ($adapter in $adapters) {
                            if ($adapter.NetworkName -like "*$searchInput*") {
                                $vms += $vm
                                break
                            }
                        }
                    }
                    
                    if ($vms) {
                        Write-Output "Se encontraron VMs conectadas al portgroup '$searchInput'"
                    }
                }
            }
            'DATASTORE' {
                Write-Output "Buscando VMs en el datastore: $searchInput"
                $datastore = Get-Datastore -Name $searchInput
                $vms = Get-VM | Where-Object {
                    $_.DatastoreIdList -contains $datastore.Id
                }
            }
            'VLAN' {
                # Extraer el número de VLAN del input
                $vlanId = $searchInput -replace '(?i)vlan\s*', ''
                $vlanId = [int]$vlanId
                Write-Output "Buscando VMs en VLAN $vlanId"
                
                # Buscar todos los portgroups con ese VLAN ID
                $pgNames = @()
                
                # Buscar en portgroups estándar
                $standardPGs = Get-VirtualPortGroup -Standard -ErrorAction SilentlyContinue | Where-Object { $_.VlanId -eq $vlanId }
                $pgNames += $standardPGs.Name
                
                # Buscar en portgroups distribuidos
                try {
                    $allDPGs = Get-VDPortgroup -ErrorAction SilentlyContinue
                    foreach ($dpg in $allDPGs) {
                        $vlanConfig = $dpg.ExtensionData.Config.DefaultPortConfig.Vlan
                        if ($vlanConfig -and $vlanConfig.VlanId -eq $vlanId) {
                            $pgNames += $dpg.Name
                        }
                    }
                }
                catch {
                    # Si no hay switch distribuido, continuar
                }
                
                # Eliminar duplicados
                $pgNames = $pgNames | Select-Object -Unique
                
                if ($pgNames.Count -gt 0) {
                    Write-Output "Portgroups encontrados en VLAN ${vlanId}: $($pgNames -join ', ')"
                    
                    # Buscar VMs conectadas a estos portgroups
                    $allVMs = Get-VM
                    $vms = @()
                    
                    foreach ($vm in $allVMs) {
                        $adapters = Get-NetworkAdapter -VM $vm
                        foreach ($adapter in $adapters) {
                            if ($pgNames -contains $adapter.NetworkName) {
                                $vms += $vm
                                break
                            }
                        }
                    }
                }
                else {
                    Write-Output "No se encontraron portgroups con VLAN ID $vlanId"
                }
            }
            'UNKNOWN' {
                Write-Output "Tipo de búsqueda no reconocido. Intentando búsqueda por nombre..."
                $vms = Get-VM -Name "*$searchInput*" -ErrorAction SilentlyContinue
            }
        }

        if ($vms) {
            # Eliminar VMs duplicadas
            $vms = $vms | Select-Object -Unique
            
            Write-Output "`nSe encontraron $($vms.Count) VM(s):"
            foreach ($vm in $vms) {
                $vmInfo = Get-DetailedVMInfo -vm $vm -AllData:$AllData
                $vmInfo | Format-List
                Write-Output ("=" * 60)
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
