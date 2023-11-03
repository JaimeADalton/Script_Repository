#!/bin/bash

# Path to the Nagios configuration file.
NAGIOS_CONFIG="your_config_file.cfg"

declare -A hostgroup_members

# Function to add new member to hostgroup in config
add_new_member_to_hostgroup() {
    local hostgroup=$1
    local new_members=$2
    local config_file=$3

    # Temporal backup of the file
    cp "$config_file" "$config_file.bak"

    # Add new member to the hostgroup definition
    awk -v hostgroup="$hostgroup" -v new_members="$new_members" '
        $1 == "define" && $2 == "hostgroup{" {
            capture = 1
        }
        capture && /}/ {
            print "        members         " new_members
            capture = 0
        }
        { print }
    ' "$config_file.bak" > "$config_file"

    # Remove temporary file
    rm -f "$config_file.bak"
}

# Detect CSV separator function
detect_csv_separator() {
    local file="$1"
    # Assume the separator is a comma, semicolon, or tab
    local separators=',;        '
    local first_line=$(head -n 1 "$file")
    for sep in $(echo $separators | fold -w1); do
        if [[ "$first_line" == *"$sep"* ]]; then
            echo "$sep"
            return
        fi
    done
}

# Detect the separator
CSV_SEPARATOR=$(detect_csv_separator "hosts.csv")

if [ -z "$CSV_SEPARATOR" ]; then
    echo "Cannot detect CSV separator."
    exit 1
fi

# Read the CSV file and populate the hostgroup_members associative array
while IFS="$CSV_SEPARATOR" read -r host_name alias address hostgroup
do
    # Skip the header line
    if [ "$host_name" != "host_name" ]; then
        # Add host to the Nagios configuration
        cat >> "$NAGIOS_CONFIG" << EOF
define host{
    use             generic-switch
    host_name       $host_name
    alias           $alias
    address         $address
    hostgroups      $hostgroup
}
EOF

        # Add service associated with the host
        cat >> "$NAGIOS_CONFIG" << EOF
define service{
    use                     generic-service
    host_name               $host_name
    service_description     PING
    check_command           check_ping!200.0,20%!600.0,80%
}
EOF

        # Add the host to the hostgroup members array
        if [[ -n "${hostgroup_members["$hostgroup"]}" ]]; then
            hostgroup_members["$hostgroup"]+=","
        fi
        hostgroup_members["$hostgroup"]+="$host_name"
    fi
done < hosts.csv

# Add or update hostgroup definitions in the Nagios configuration
for hostgroup in "${!hostgroup_members[@]}"; do
    members="${hostgroup_members["$hostgroup"]}"
    hostgroup_exists=$(grep -E "^\s*define\s+hostgroup\s*\{\s*hostgroup_name\s+$hostgroup" "$NAGIOS_CONFIG")
    if [[ -z $hostgroup_exists ]]; then
        # If the hostgroup doesn't exist, add it
        cat >> "$NAGIOS_CONFIG" << EOF
define hostgroup{
    hostgroup_name  $hostgroup
    alias           New Hostgroup
    members         $members
}
EOF
    else
        # If the hostgroup exists, update it
        add_new_member_to_hostgroup "$hostgroup" "$members" "$NAGIOS_CONFIG"
    fi
done

echo "Nagios configuration updated successfully."
