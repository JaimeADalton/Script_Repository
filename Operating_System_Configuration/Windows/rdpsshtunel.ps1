Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'

function Hide-ConsoleWindow {
    $consolePtr = [Console.Window]::GetConsoleWindow()
    [Console.Window]::ShowWindow($consolePtr, 0)
}

Hide-ConsoleWindow


Add-Type -AssemblyName System.Windows.Forms

# Paso 1: Solicitar al usuario la dirección IP de destino
$ipForm = New-Object System.Windows.Forms.Form
$ipForm.Text = "Introduce la dirección IP"
$ipForm.Size = New-Object System.Drawing.Size(316, 120)
$ipForm.StartPosition = "CenterScreen"

$ipTextBox = New-Object System.Windows.Forms.TextBox
$ipTextBox.Location = New-Object System.Drawing.Point(20, 20)
$ipTextBox.Size = New-Object System.Drawing.Size(260, 20)
$ipForm.Controls.Add($ipTextBox)

$ipButton = New-Object System.Windows.Forms.Button
$ipButton.Location = New-Object System.Drawing.Point(100, 50)
$ipButton.Size = New-Object System.Drawing.Size(100, 30)
$ipButton.Text = "Aceptar"
$ipButton.Add_Click({
    $ipForm.Close()
})

$ipForm.Controls.Add($ipButton)

$ipForm.ShowDialog() | Out-Null

$ipAddress = $ipTextBox.Text

# Paso 2: Crear el túnel SSH hacia el servidor bastión
$bastionServer = "192.168.252.50"
$bastionUsername = "jaimedalton"
$privateKeyPath = "C:\Users\jaimedalton\Documents\Keys\jaimedalton_srvbastionssh.key"
$localPort = Get-Random -Minimum 30000 -Maximum 65535

$sshCommand = "ssh -L " + $localPort + ":" + $ipAddress + ":3389 -i " + $privateKeyPath + " " + $bastionUsername + "@" + $bastionServer
$sshProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $sshCommand" -WindowStyle Hidden -PassThru

# Paso 3: Esperar a que se establezca el túnel SSH
Write-Host "Conectándose a través del túnel SSH..."

# Esperar hasta que el puerto local esté abierto y listo para recibir conexiones
$portOpen = $false
while (-not $portOpen) {
    $portOpen = Test-NetConnection -ComputerName "localhost" -Port $localPort -InformationLevel Quiet
    Start-Sleep -Seconds 1
}

# Paso 4: Abrir el cliente de Escritorio Remoto de Windows
$mstscPath = "C:\Windows\System32\mstsc.exe"
#Start-Process -FilePath $mstscPath -ArgumentList "/v:$ipAddress" -Wait

# Conexión establecida
Write-Host "Conexión SSH establecida a través del puerto local $localPort"

# Abrir el cliente de Escritorio Remoto y conectarse a través del puerto local
$mstscProcess = Start-Process -FilePath $mstscPath -ArgumentList "/v:localhost:$localPort" -PassThru

# Esperar a que finalice el proceso mstsc.exe
$mstscProcess.WaitForExit()

# Cuando el proceso mstsc.exe finaliza, cerrar el proceso del túnel SSH
if ($sshProcess) {
    Stop-Process -Id $sshProcess.Id -Force
    Write-Host "Túnel SSH cerrado"
}
