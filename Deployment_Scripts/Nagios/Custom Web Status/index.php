<?php
// Directory containing Nagios configuration files
$configDir = '/usr/local/nagios/etc/objects';

// Function to parse host definitions from a file
function parseHostDefinitions($fileContent) {
    $hosts = [];
    $currentHost = null;
    foreach (explode("\n", $fileContent) as $line) {
        $line = trim($line);
        if (preg_match('/^define host {/', $line)) {
            $currentHost = [];
        } elseif ($line === '}' && $currentHost !== null) {
            $hosts[] = $currentHost;
            $currentHost = null;
        } elseif ($currentHost !== null && preg_match('/^(\w+)\s+(.+)$/', $line, $matches)) {
            $key = $matches[1];
            $value = trim($matches[2]);
            $currentHost[$key] = $value;
        }
    }
    return $hosts;
}

// Get all .cfg files in the directory
$configFiles = glob($configDir . '/*.cfg');

// Parse all host definitions
$allHosts = [];
foreach ($configFiles as $file) {
    $fileContent = file_get_contents($file);
    $allHosts = array_merge($allHosts, parseHostDefinitions($fileContent));
}

// Search functionality
$searchTerm = isset($_GET['search']) ? $_GET['search'] : '';
$filteredHosts = $allHosts;
if (!empty($searchTerm)) {
    $filteredHosts = array_filter($allHosts, function($host) use ($searchTerm) {
        foreach ($host as $value) {
            if (stripos($value, $searchTerm) !== false) {
                return true;
            }
        }
        return false;
    });
}

// HTML output starts here
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Nagios Host Status</title>
    <style>
        .status-ok { background-color: #90EE90; }
        .status-down { background-color: #FFB6C1; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid black; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script>
    function updateHostStatus(hostId) {
        $.ajax({
            url: 'ping.php',
            type: 'GET',
            data: { hostId: hostId },
            success: function(response) {
                var result = JSON.parse(response);
                var row = $('#host-' + hostId);
                row.removeClass('status-ok status-down').addClass(result.status === 'OK' ? 'status-ok' : 'status-down');
                row.find('.status').html(result.status + (result.time !== null ? ' (' + result.time + ' ms)' : ''));
            }
        });
    }

    $(document).ready(function() {
        $('.host-row').each(function() {
            var hostId = $(this).data('host-id');
            updateHostStatus(hostId);
        });
    });
    </script>
</head>
<body>
    <form method="get">
        <input type="text" name="search" value="<?= htmlspecialchars($searchTerm) ?>" placeholder="Search hosts...">
        <input type="submit" value="Search">
    </form>

    <table>
        <tr>
            <th>Host Name</th>
            <th>Descripcion</th>
            <th>Direccion IP</th>
            <th>Edificio</th>
            <th>Otros Atributos</th>
            <th>Estado</th>
        </tr>
        <?php foreach ($filteredHosts as $index => $host): ?>
        <tr id="host-<?= $index ?>" class="host-row" data-host-id="<?= $index ?>">
            <td><?= isset($host['host_name']) ? htmlspecialchars($host['host_name']) : '' ?></td>
            <td><?= isset($host['alias']) ? htmlspecialchars($host['alias']) : '' ?></td>
            <td><?= isset($host['address']) ? htmlspecialchars($host['address']) : '' ?></td>
            <td><?= isset($host['hostgroups']) ? htmlspecialchars($host['hostgroups']) : '' ?></td>
            <td>
                <?php
                foreach ($host as $key => $value) {
                    if (!in_array($key, ['host_name', 'alias', 'address', 'use', 'hostgroups'])) {
                        echo htmlspecialchars($key) . ": " . htmlspecialchars($value) . "<br>";
                    }
                }
                ?>
            </td>
            <td class="status">Checking...</td>
        </tr>
        <?php endforeach; ?>
    </table>
</body>
</html>
