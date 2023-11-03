#!/usr/bin/python3
import os
import re
import argparse
from collections import defaultdict
import glob
import sys

# Exception classes for argument parsing simulation
class ArgumentParserError(Exception):
    """ Exception for argument parsing """
    pass

class ThrowingArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise ArgumentParserError(message)

# Function to parse log entries
def parse_log_entry(entry):
    log_data = defaultdict(str)
    patterns = {
        'type': r'type=([^ ]+)',
        'timestamp': r'msg=audit\(([^)]+)\):',
        'pid': r'pid=([^ ]+)',
        'uid': r'uid=([^ ]+)',
        'auid': r'auid=([^ ]+)',
        'ses': r'ses=([^ ]+)',
        'acct': r'acct="([^"]+)"',
        'exe': r'exe="([^"]+)"',
        'hostname': r'hostname=([^ ]+)',
        'addr': r'addr=([^ ]+)',
        'terminal': r'terminal=([^ ]+)',
        'res': r'res=([^ ]+)',
        'uid_root': r'UID="([^"]+)"'  # Added pattern for UID="root"
    }
    for key, pattern in patterns.items():
        match = re.search(pattern, entry)
        if match:
            log_data[key] = match.group(1)
    return log_data

# Function to display the parsed log data
def display_log_data(log_data):
    for key, value in log_data.items():
        print(f"{key.capitalize()}: {value}")
    if 'uid_root' in log_data:
        print(f'UID: {log_data["uid_root"]}')
    print('-' * 40)

# Function to create a command line argument parser with a help menu
def create_parser():
    parser = ThrowingArgumentParser(description='Audit Log Parser')
    parser.add_argument('--file', nargs='?', help='Path to the audit log file', default='/var/log/audit/audit.log*')
    parser.add_argument('--type', help='Filter by event type (e.g., LOGIN, USER_ACCT)')
    parser.add_argument('--user', help='Filter by user account (e.g., root, manuelcuesta)')
    parser.add_argument('--ip', help='Filter by IP address (e.g., 192.168.1.1)')
    parser.add_argument('--result', help='Filter by result (e.g., success, fail)')
    
    # Add filters for specific types
    parser.add_argument('--cred-acq', action='store_true', help='Filter by CRED_ACQ type')
    parser.add_argument('--type-timestamp', help='Filter by Timestamp')
    parser.add_argument('--type-pid', help='Filter by Pid')
    parser.add_argument('--type-uid', help='Filter by Uid')
    parser.add_argument('--type-auid', help='Filter by Auid')
    parser.add_argument('--type-ses', help='Filter by Ses')
    parser.add_argument('--type-acct', help='Filter by Acct')
    parser.add_argument('--type-exe', help='Filter by Exe')
    parser.add_argument('--type-hostname', help='Filter by Hostname')
    parser.add_argument('--type-addr', help='Filter by Addr')
    parser.add_argument('--type-terminal', help='Filter by Terminal')
    parser.add_argument('--type-res', help='Filter by Res')
    parser.add_argument('--type-uid-root', help='Filter by Uid_root')
    
    return parser

# Function to check if the script is being run as root
def check_root_privileges():
    if os.geteuid() != 0:
        print("This script requires root privileges to read the audit log file.")
        sys.exit(1)

# Function to read log files and parse entries
def read_and_parse_log_files(file_path_pattern):
    parsed_logs = []
    try:
        for file_path in glob.glob(file_path_pattern):
            with open(file_path, 'r') as file:
                parsed_logs.extend(parse_log_entry(entry) for entry in file if entry.strip())
    except PermissionError as e:
        print(f"Permission error: {e}. You do not have permission to read the log file.")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)
    return parsed_logs

# Function to filter log data based on command line arguments
def filter_log_data(parsed_logs, args):
    filtered_logs = []
    for log in parsed_logs:
        if args.type and log['type'] != args.type:
            continue
        if args.user and log['acct'] != args.user:
            continue
        if args.ip and log['addr'] != args.ip:
            continue
        if args.result and log['res'] != args.result:
            continue
        if args.cred_acq and log['type'] != 'CRED_ACQ':
            continue
        if args.type_timestamp and log['timestamp'] != args.type_timestamp:
            continue
        if args.type_pid and log['pid'] != args.type_pid:
            continue
        if args.type_uid and log['uid'] != args.type_uid:
            continue
        if args.type_auid and log['auid'] != args.type_auid:
            continue
        if args.type_ses and log['ses'] != args.type_ses:
            continue
        if args.type_acct and log['acct'] != args.type_acct:
            continue
        if args.type_exe and log['exe'] != args.type_exe:
            continue
        if args.type_hostname and log['hostname'] != args.type_hostname:
            continue
        if args.type_addr and log['addr'] != args.type_addr:
            continue
        if args.type_terminal and log['terminal'] != args.type_terminal:
            continue
        if args.type_res and log['res'] != args.type_res:
            continue
        if args.type_uid_root and 'uid_root' in log and log['uid_root'] != args.type_uid_root:
            continue
        filtered_logs.append(log)
    return filtered_logs

# Function to simulate command line argument input and the help menu
def simulate_command_line(args):
    parser = create_parser()
    try:
        args = parser.parse_args(args)
    except ArgumentParserError as e:
        print(str(e))
        sys.exit(1)

    parsed_logs = read_and_parse_log_files(args.file)
    filtered_logs = filter_log_data(parsed_logs, args)
    for log in filtered_logs:
        display_log_data(log)

# Main function to handle the argument parsing and exceptions
def main(args):
    try:
        check_root_privileges()  # Check for root privileges
        simulate_command_line(args)
    except ArgumentParserError as e:
        print(f"Error parsing arguments: {e}")
        sys.exit(1)
    except PermissionError as e:
        print(f"Permission error: {e}. You do not have permission to read the log file.")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)

# The entry point of the script
if __name__ == "__main__":
    main(sys.argv[1:])
