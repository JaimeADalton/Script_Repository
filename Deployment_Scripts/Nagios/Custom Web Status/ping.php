<?php
session_start();

if (!isset($_SESSION['hosts'])) {
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

    $_SESSION['hosts'] = $allHosts;
}

function pingHost($ip) {
    $pingResult = exec("ping -c 1 -W 1 " . escapeshellarg($ip), $output, $returnVar);
    if ($returnVar === 0) {
        preg_match('/time=(\d+\.?\d*) ms/', $pingResult, $matches);
        $time = isset($matches[1]) ? floatval($matches[1]) : null;
        return ['status' => 'OK', 'time' => $time];
    } else {
        return ['status' => 'DOWN', 'time' => null];
    }
}

if (isset($_GET['hostId']) && isset($_SESSION['hosts'][$_GET['hostId']])) {
    $host = $_SESSION['hosts'][$_GET['hostId']];
    $result = pingHost($host['address']);
    echo json_encode($result);
} else {
    echo json_encode(['error' => 'Invalid host ID']);
}
