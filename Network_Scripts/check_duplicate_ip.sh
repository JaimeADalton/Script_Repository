###
#~USE ./check_duplicate_ip.sh 192.168.1.100
#!/bin/bash

# Function to check if arping is installed
check_arping_installed() {
    if ! command -v arping &> /dev/null; then
        echo "arping is not installed. Please install it before running this script."
        exit 1
    fi
}

# Function to validate the IP address format
validate_ip() {
    local ip="$1"
    # Using regex to validate IP address format
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "Invalid IP address format: $ip"
        exit 1
    fi
}

# Function to check for duplicate IP
check_duplicate_ip() {
    local ip="$1"
    local arping_output

    arping_output=$(arping -D -c 3 -w 1 -I eth0 "$ip" 2>&1)

    if [[ $arping_output =~ "Unicast reply from" ]]; then
        echo "IP address $ip is already in use."
    elif [[ $arping_output =~ "Sent 3 probes" ]]; then
        echo "IP address $ip is available."
    else
        echo "Error while checking IP address $ip:"
        echo "$arping_output"
    fi
}

# Main function
main() {
    check_arping_installed

    # Check if an IP address is provided as an argument
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <IP address>"
        exit 1
    fi

    # Get the IP address argument
    local ip="$1"

    # Validate the IP address format
    validate_ip "$ip"

    # Check for duplicate IP
    check_duplicate_ip "$ip"
}

# Run the script
main "$@"



