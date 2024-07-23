<?php
session_start();

if (!isset($_SESSION["hosts"])) {
    $configDir = "/usr/local/nagios/etc/objects";

    function parseHostDefinitions($fileContent)
    {
        $hosts = [];
        $currentHost = null;
        foreach (explode("\n", $fileContent) as $line) {
            $line = trim($line);
            if (preg_match("/^define host {/", $line)) {
                $currentHost = [];
            } elseif ($line === "}" && $currentHost !== null) {
                $hosts[] = $currentHost;
                $currentHost = null;
            } elseif (
                $currentHost !== null &&
                preg_match('/^(\w+)\s+(.+)$/', $line, $matches)
            ) {
                $key = $matches[1];
                $value = trim($matches[2]);
                $currentHost[$key] = $value;
            }
        }
        return $hosts;
    }

    $configFiles = glob($configDir . "/*.cfg");

    $allHosts = [];
    foreach ($configFiles as $file) {
        $fileContent = file_get_contents($file);
        $allHosts = array_merge($allHosts, parseHostDefinitions($fileContent));
    }

    usort($allHosts, function ($a, $b) {
        return strcasecmp($a["host_name"], $b["host_name"]);
    });

    $_SESSION["hosts"] = $allHosts;
}

function pingAllHosts($hosts)
{
    $results = [];
    $processes = [];

    foreach ($hosts as $id => $host) {
        $ip = $host["address"];
        $descriptorspec = [
            0 => ["pipe", "r"],
            1 => ["pipe", "w"],
            2 => ["pipe", "w"],
        ];
        $processes[$id] = proc_open(
            "ping -c 3 -i 0.8 -W 1 " . escapeshellarg($ip),
            $descriptorspec,
            $pipes[$id]
        );

        if (is_resource($processes[$id])) {
            stream_set_blocking($pipes[$id][1], 0);
            stream_set_blocking($pipes[$id][2], 0);
        }
    }

    $running = count($processes);
    while ($running > 0) {
        foreach ($processes as $id => $process) {
            if (!is_resource($process)) {
                continue;
            }

            $status = proc_get_status($process);
            if (!$status["running"]) {
                $output = stream_get_contents($pipes[$id][1]);
                fclose($pipes[$id][1]);
                fclose($pipes[$id][2]);
                proc_close($process);

                preg_match("/(\d+)% packet loss/", $output, $matches);
                $packetLoss = isset($matches[1]) ? intval($matches[1]) : 100;

                preg_match(
                    "/min\/avg\/max\/mdev = ([\d.]+)\/([\d.]+)\/([\d.]+)\/([\d.]+)/",
                    $output,
                    $matches
                );
                $avgTime = isset($matches[2]) ? floatval($matches[2]) : null;

                if ($packetLoss < 100) {
                    $status = $packetLoss < 50 ? "OK" : "DEGRADED";
                } else {
                    $status = "DOWN";
                }

                $results[$id] = [
                    "status" => $status,
                    "time" => $avgTime,
                    "packetLoss" => $packetLoss,
                ];

                unset($processes[$id]);
                $running--;
            }
        }
        usleep(10000);
    }

    return $results;
}

if (isset($_GET["getAllResults"])) {
    $results = pingAllHosts($_SESSION["hosts"]);
    echo json_encode($results);
    exit();
}

$searchTerm = isset($_GET["search"]) ? $_GET["search"] : "";
$filteredHosts = $_SESSION["hosts"];
if (!empty($searchTerm)) {
    $filteredHosts = array_filter($filteredHosts, function ($host) use (
        $searchTerm
    ) {
        foreach ($host as $value) {
            if (stripos($value, $searchTerm) !== false) {
                return true;
            }
        }
        return false;
    });
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Nagios Host Status</title>
    <style>
        .status-ok { background-color: #90EE90; }
        .status-degraded { background-color: #FFD700; }
        .status-down { background-color: #FFB6C1; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid black; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script>
    function updateAllHostStatus() {
        $.ajax({
            url: window.location.href,
            type: 'GET',
            data: { getAllResults: true },
            success: function(response) {
                var results = JSON.parse(response);
                var rows = [];
                for (var hostId in results) {
                    var result = results[hostId];
                    var row = $('#host-' + hostId);
                    row.removeClass('status-ok status-degraded status-down')
                       .addClass('status-' + result.status.toLowerCase());
                    var statusText = result.status;
                    if (result.time !== null) {
                        statusText += ' (' + result.time.toFixed(2) + ' ms)';
                    }
                    statusText += ' - ' + result.packetLoss + '% packet loss';
                    row.find('.status').html(statusText);
                    rows.push({
                        element: row,
                        status: result.status,
                        hostName: row.find('td:first').text()
                    });
                }

                rows.sort(function(a, b) {
                    if (a.status === 'DOWN' && b.status !== 'DOWN') return -1;
                    if (a.status !== 'DOWN' && b.status === 'DOWN') return 1;
                    if (a.status === 'DEGRADED' && b.status === 'OK') return -1;
                    if (a.status === 'OK' && b.status === 'DEGRADED') return 1;
                    return a.hostName.localeCompare(b.hostName);
                });

                var tbody = $('tbody');
                rows.forEach(function(row) {
                    tbody.append(row.element);
                });

                console.log('All hosts updated and sorted');
            }
        });
    }

    $(document).ready(function() {
        updateAllHostStatus();
    });
    </script>
</head>
<body>
    <form method="get">
        <input type="text" name="search" value="<?= htmlspecialchars(
            $searchTerm
        ) ?>" placeholder="Search hosts...">
        <input type="submit" value="Search">
    </form>

    <table>
        <thead>
            <tr>
                <th>Host Name</th>
                <th>Descripcion</th>
                <th>Direccion IP</th>
                <th>Edificio</th>
                <th>Otros Atributos</th>
                <th>Estado</th>
            </tr>
        </thead>
        <tbody>
            <?php foreach ($filteredHosts as $index => $host): ?>
            <tr id="host-<?= $index ?>" class="host-row" data-host-id="<?= $index ?>">
                <td><?= isset($host["host_name"])
                    ? htmlspecialchars($host["host_name"])
                    : "" ?></td>
                <td><?= isset($host["alias"])
                    ? htmlspecialchars($host["alias"])
                    : "" ?></td>
                <td><?= isset($host["address"])
                    ? htmlspecialchars($host["address"])
                    : "" ?></td>
                <td><?= isset($host["hostgroups"])
                    ? htmlspecialchars($host["hostgroups"])
                    : "" ?></td>
                <td>
                    <?php foreach ($host as $key => $value) {
                        if (
                            !in_array($key, [
                                "host_name",
                                "alias",
                                "address",
                                "use",
                                "hostgroups",
                            ])
                        ) {
                            $formattedKey = ucfirst(substr($key, 1));
                            echo htmlspecialchars($formattedKey) .
                                ": " .
                                htmlspecialchars($value) .
                                "<br>";
                        }
                    } ?>
                </td>
                <td class="status">Checking...</td>
            </tr>
            <?php endforeach; ?>
        </tbody>
    </table>
</body>
</html>
