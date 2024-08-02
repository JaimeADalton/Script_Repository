import getpass
import re
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim
import ssl

# Define fixed user for vCenter
vCenterUser = "Change_Me_To_Username"
vCenterServer = "Change_Me_To_FQDN"

# Request password from user
vCenterPassword = getpass.getpass(f"Enter password for {vCenterUser}: ")

# Connect to vCenter server
try:
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    
    si = SmartConnect(host=vCenterServer,
                      user=vCenterUser,
                      pwd=vCenterPassword,
                      sslContext=context)
    print(f"Successfully connected to vCenter as {vCenterUser}")
except Exception as e:
    print(f"Could not connect to vCenter server: {e}")
    exit(1)

def get_detailed_vm_info(vm):
    return {
        "Name": vm.summary.config.name,
        "RAM (GB)": round(vm.summary.config.memorySizeMB / 1024, 2),
        "CPU": vm.summary.config.numCpu,
        "State": str(vm.summary.runtime.powerState),
        "Used Space (GB)": round(vm.summary.storage.committed / (1024**3), 2),
        "MAC Address": ", ".join([nic.macAddress for nic in vm.guest.net]),
        "IP Address": ", ".join([nic.ipAddress[0] for nic in vm.guest.net if nic.ipAddress]),
        "Host": vm.runtime.host.name,
        "Datastore": ", ".join([ds.name for ds in vm.datastore]),
        "Snapshots": len(vm.snapshot.rootSnapshotList) if vm.snapshot else 0
    }

def remove_leading_trailing_spaces(input_string):
    return input_string.strip()

def get_input_type(input_str):
    if not input_str:
        return 'UNKNOWN'
    
    input_str = input_str.strip()
    
    if re.match(r'^(\d{1,3}\.){3}\d{1,3}$', input_str):
        octets = input_str.split('.')
        if len(octets) == 4 and all(0 <= int(octet) <= 255 for octet in octets):
            return 'IP Completa'
    
    if re.match(r'^(\d{1,3}\.){0,2}\d{1,3}$', input_str):
        octets = input_str.split('.')
        if all(octet.isdigit() and 0 <= int(octet) <= 255 for octet in octets):
            return 'IP Parcial'
    
    if re.match(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$', input_str):
        return 'MAC Completa'
    
    if re.match(r'^([0-9A-Fa-f]{1,2}[:-]){0,5}[0-9A-Fa-f]{1,2}$', input_str):
        return 'MAC Parcial'
    
    if re.match(r'^[a-zA-Z0-9\-_\.]+$', input_str):
        return 'NAME'
    
    return 'UNKNOWN'

def get_vms(content, search_input, search_type):
    container = content.viewManager.CreateContainerView(content.rootFolder, [vim.VirtualMachine], True)
    vms = []
    for vm in container.view:
        if search_type == 'IP Completa':
            if search_input in [nic.ipAddress[0] for nic in vm.guest.net if nic.ipAddress]:
                vms.append(vm)
        elif search_type == 'IP Parcial':
            if any(search_input in ip for nic in vm.guest.net for ip in nic.ipAddress):
                vms.append(vm)
        elif search_type == 'MAC Completa':
            if search_input in [nic.macAddress for nic in vm.guest.net]:
                vms.append(vm)
        elif search_type == 'MAC Parcial':
            if any(search_input in mac for nic in vm.guest.net for mac in nic.macAddress):
                vms.append(vm)
        elif search_type == 'NAME':
            if search_input.lower() in vm.summary.config.name.lower():
                vms.append(vm)
    return vms

try:
    content = si.RetrieveContent()
    while True:
        search_input = remove_leading_trailing_spaces(input("Enter IP, MAC or VM name (or 'q' to quit): "))
        if search_input.lower() == 'q':
            break
        
        search_type = get_input_type(search_input)
        vms = get_vms(content, search_input, search_type)
        
        if vms:
            for vm in vms:
                vm_info = get_detailed_vm_info(vm)
                for key, value in vm_info.items():
                    print(f"{key}: {value}")
                print()  # Empty line to separate VMs
        else:
            print("No virtual machines found with the specified criteria.")
        print()  # Empty line to separate queries

except Exception as e:
    print(f"An error occurred during script execution: {e}")

finally:
    try:
        Disconnect(si)
        print("Session closed. Thank you for using the script.")
    except Exception as e:
        print(f"Error disconnecting from vCenter server: {e}")
