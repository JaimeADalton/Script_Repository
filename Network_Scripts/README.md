# Network_Scripts

Collection of scripts for network configuration, scanning and monitoring.

## Subdirectories

- `IPTables` - Utilities and documentation for iptables. See [IPTables/README](IPTables/README.md).
- `Netplan` - Scripts to assist with Netplan configurations. See [Netplan/README](Netplan/README.md).
- `Network` - Generator for classic `interfaces` files.
- `Nmap` - Asynchronous Nmap scanning tools. See [Nmap/README](Nmap/README.md).

## Scripts

- `NetworkMonitor_icmp.py` - Monitor hosts via ICMP.
- `OS_Detector.sh` - Guess the operating system based on TTL values.
- `Protocol_ICMP-SNMP_check*` - Scripts to check ICMP and SNMP reachability.
- `scan_network*.py` and `scan_network_p22.py` - Network scanning utilities.
- `scanicmp.sh` - Simple ping sweep script.
- `check_duplicate_ip.sh` - Detect duplicate IP addresses on the LAN.
- `comparar_rutas_netplan.*` - Compare Netplan route files.
- `configurar_bond.sh` - Configure network bonding.
- `get_macaddress.py` - Obtain a MAC address from an IP.
- `Table_Protocol_ICMP-SNMP_Comunity_Check.py` - Build protocol check tables.
