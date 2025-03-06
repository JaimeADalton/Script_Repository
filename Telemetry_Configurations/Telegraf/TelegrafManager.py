#!/usr/bin/env python3
import os
import re
import sys
import argparse
import logging
import signal
import configparser
import subprocess
import pwd
import grp
from pathlib import Path
try:
    import psutil
    from pysnmp.hlapi import *
    from pysnmp.smi import builder, view, compiler
except ImportError as e:
    print(f"Missing required dependency: {e}")
    print("Install dependencies with: pip install pysnmp psutil")
    sys.exit(1)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger('telegraf_manager')

class TelegrafManager:
    def __init__(self, config_file=None):
        # Default configuration
        self.config = {
            'telegraf_dir': '/etc/telegraf/telegraf.d',
            'include_ip_in_alias': False,
            'snmp_community': 'GestionGrp',  # Default safer community
            'snmp_version': 2,
            'snmp_timeout': 5,
            'snmp_retries': 1,
            'polling_interval': '30s'
        }

        # Load configuration from file if provided
        if config_file and os.path.exists(config_file):
            self._load_config(config_file)

        # Initialize MIBs
        self.mib_view_controller = self._setup_mibs()
        
        # Get telegraf user and group IDs
        try:
            self.telegraf_uid = pwd.getpwnam('telegraf').pw_uid
            self.telegraf_gid = grp.getgrnam('telegraf').gr_gid
        except KeyError:
            logger.error("Telegraf user or group not found. Make sure telegraf is installed.")
            sys.exit(1)

    def _load_config(self, config_file):
        """Load configuration from file"""
        try:
            parser = configparser.ConfigParser()
            parser.read(config_file)

            if 'TelegrafManager' in parser:
                for key, value in parser['TelegrafManager'].items():
                    # Convert boolean strings to actual booleans
                    if value.lower() in ('true', 'false'):
                        self.config[key] = value.lower() == 'true'
                    # Convert numeric strings to integers
                    elif value.isdigit():
                        self.config[key] = int(value)
                    else:
                        self.config[key] = value

            logger.info(f"Configuration loaded from {config_file}")
        except Exception as e:
            logger.error(f"Error loading configuration: {e}")

    def _setup_mibs(self):
        """Set up MIB handling"""
        try:
            mib_builder = builder.MibBuilder()
            mib_sources = mib_builder.getMibSources() + (
                builder.DirMibSource('/usr/share/snmp/mibs'),
            )
            mib_builder.setMibSources(*mib_sources)
            compiler.addMibCompiler(mib_builder)

            try:
                mib_builder.loadModules('IF-MIB', 'RFC1213-MIB')
            except Exception as e:
                logger.error(f"Error loading MIBs: {e}")
                sys.exit(1)

            return view.MibViewController(mib_builder)
        except Exception as e:
            logger.error(f"Failed to set up MIBs: {e}")
            sys.exit(1)

    def _is_valid_ip(self, ip):
        """Validate IP address format"""
        pattern = re.compile(r"^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$")
        return pattern.match(ip) is not None

    def _prompt_yes_no(self, prompt):
        """Prompt user for yes/no response"""
        while True:
            response = input(f"{prompt} (y/n): ").strip().lower()
            if response in ('y', 'yes'):
                return True
            elif response in ('n', 'no'):
                return False
            else:
                print("Invalid response. Enter 'y' or 'n'.")

    def _sanitize_name(self, name):
        """Sanitize input to prevent path traversal"""
        return re.sub(r'[^\w\-\.]', '_', name)
    
    def _set_proper_permissions(self, path, is_directory=False):
        """Set appropriate permissions and ownership for files and directories"""
        try:
            if is_directory:
                os.chmod(path, 0o755)  # rwxr-xr-x for directories
            else:
                os.chmod(path, 0o644)  # rw-r--r-- for files
            
            # Set telegraf user and group ownership
            os.chown(path, self.telegraf_uid, self.telegraf_gid)
            logger.debug(f"Set permissions for {path}: {'755' if is_directory else '644'} telegraf:telegraf")
            return True
        except Exception as e:
            logger.error(f"Error setting permissions for {path}: {e}")
            return False

    def snmp_get(self, ip, oid):
        """Perform SNMP GET operation"""
        try:
            # Map version number to SNMP model
            mp_model = 0 if self.config['snmp_version'] == 1 else 1

            iterator = getCmd(
                SnmpEngine(),
                CommunityData(self.config['snmp_community'], mpModel=mp_model),
                UdpTransportTarget((ip, 161),
                                  timeout=self.config['snmp_timeout'],
                                  retries=self.config['snmp_retries']),
                ContextData(),
                ObjectType(ObjectIdentity(oid).resolveWithMib(self.mib_view_controller))
            )

            error_indication, error_status, error_index, var_binds = next(iterator)

            if error_indication:
                logger.error(f"SNMP GET error: {error_indication}")
                return None
            elif error_status:
                logger.error(f"SNMP error: {error_status.prettyPrint()}")
                return None

            return var_binds[0][1].prettyPrint() if var_binds else None
        except Exception as e:
            logger.error(f"Exception in SNMP GET: {e}")
            return None

    def snmp_walk(self, ip, oid):
        """Perform SNMP WALK operation"""
        result = []
        try:
            # Map version number to SNMP model
            mp_model = 0 if self.config['snmp_version'] == 1 else 1

            for (error_indication, error_status, error_index, var_binds) in nextCmd(
                SnmpEngine(),
                CommunityData(self.config['snmp_community'], mpModel=mp_model),
                UdpTransportTarget((ip, 161),
                                  timeout=self.config['snmp_timeout'],
                                  retries=self.config['snmp_retries']),
                ContextData(),
                ObjectType(ObjectIdentity(oid).resolveWithMib(self.mib_view_controller)),
                lexicographicMode=False
            ):
                if error_indication:
                    logger.error(f"SNMP WALK error: {error_indication}")
                    break
                elif error_status:
                    logger.error(f"SNMP error: {error_status.prettyPrint()}")
                    break
                else:
                    for var_bind in var_binds:
                        oid_obj, value = var_bind
                        oid_tuple = oid_obj.asTuple()
                        result.append((oid_tuple, value.prettyPrint()))

            return result
        except Exception as e:
            logger.error(f"Exception in SNMP WALK: {e}")
            return []

    def get_interfaces(self, agent_ip):
        """Get list of interfaces from device"""
        oid = '1.3.6.1.2.1.2.2.1.2'  # ifDescr
        interfaces = []

        snmp_results = self.snmp_walk(agent_ip, oid)
        if not snmp_results:
            return []

        base_oid = (1, 3, 6, 1, 2, 1, 2, 2, 1, 2)
        for oid_tuple, value in snmp_results:
            if oid_tuple[:len(base_oid)] == base_oid and len(oid_tuple) > len(base_oid):
                if_index = oid_tuple[len(base_oid)]
                interfaces.append((str(if_index), value))

        return interfaces

    def list_sites(self):
        """List available sites (locations)"""
        try:
            sites = sorted([
                f for f in os.listdir(self.config['telegraf_dir'])
                if os.path.isdir(os.path.join(self.config['telegraf_dir'], f))
            ])
            return sites
        except FileNotFoundError:
            logger.error(f"Directory {self.config['telegraf_dir']} does not exist")
            return []

    def create_new_site(self, site_name):
        """Create a new site directory"""
        # Sanitize site name to prevent path traversal
        site_name = self._sanitize_name(site_name)
        site_path = os.path.join(self.config['telegraf_dir'], site_name)

        if os.path.exists(site_path):
            logger.info(f"Site {site_name} already exists")
            return site_name

        try:
            os.makedirs(site_path)
            # Set proper permissions for the new directory
            self._set_proper_permissions(site_path, is_directory=True)
            logger.info(f"Site {site_name} created with permissions 755 for telegraf:telegraf")
            return site_name
        except Exception as e:
            logger.error(f"Error creating site: {e}")
            return None

    def generate_all_interfaces_config(self, agent_ip, device_alias, site_name):
        """Generate configuration for all interfaces"""
        return f"""
[[inputs.snmp]]
  precision = "{self.config['polling_interval']}"
  interval = "{self.config['polling_interval']}"
  agents = ['udp://{agent_ip}:161']
  version = {self.config['snmp_version']}
  community = "{self.config['snmp_community']}"
  timeout = "{self.config['snmp_timeout']}s"
  retries = {self.config['snmp_retries']}
  agent_host_tag = "source"

  [inputs.snmp.tags]
    device_alias = "{device_alias}"

  [[inputs.snmp.field]]
    name = "hostname"
    oid = "RFC1213-MIB::sysName.0"
    is_tag = true

  [[inputs.snmp.table]]
    name = "{site_name}"
    inherit_tags = ["hostname"]

    [[inputs.snmp.table.field]]
      name = "ifDescr"
      oid = "IF-MIB::ifDescr"
      is_tag = true

    [[inputs.snmp.table.field]]
      name = "ifHCInOctets"
      oid = "IF-MIB::ifHCInOctets"

    [[inputs.snmp.table.field]]
      name = "ifHCOutOctets"
      oid = "IF-MIB::ifHCOutOctets"
"""

    def generate_selected_interfaces_config(self, agent_ip, site_name, selected_interfaces):
        """Generate configuration for selected interfaces"""
        config = ""
        for if_index, if_descr, device_alias in selected_interfaces:
            config += f"""# Configuration for interface {if_descr} (index {if_index})
[[inputs.snmp]]
  name = "{site_name}"
  agents = ['udp://{agent_ip}:161']
  version = {self.config['snmp_version']}
  community = "{self.config['snmp_community']}"
  interval = "{self.config['polling_interval']}"
  precision = "{self.config['polling_interval']}"
  timeout = "{self.config['snmp_timeout']}s"
  retries = {self.config['snmp_retries']}
  agent_host_tag = "source"

  [inputs.snmp.tags]
    ifDescr = "{if_descr}"
    device_alias = "{device_alias}"

  [[inputs.snmp.field]]
    name = "hostname"
    oid = "RFC1213-MIB::sysName.0"
    is_tag = true

  [[inputs.snmp.field]]
    name = "ifHCInOctets"
    oid = "IF-MIB::ifHCInOctets.{if_index}"

  [[inputs.snmp.field]]
    name = "ifHCOutOctets"
    oid = "IF-MIB::ifHCOutOctets.{if_index}"

"""
        return config

    def generate_icmp_config(self, agent_ip, device_alias, site_name):
        """Generate ICMP monitoring configuration"""
        return f"""
[[inputs.ping]]
  urls = ["{agent_ip}"]
  count = 5
  interval = "10s"
  name_override = "icmp_ping"

  [inputs.ping.tags]
    device_alias = "{device_alias}"
    location = "{site_name}"

[[processors.rename]]
  [[processors.rename.replace]]
    tag = "url"
    dest = "source"
"""

    def reload_telegraf(self):
        """Reload Telegraf service"""
        try:
            for proc in psutil.process_iter(['pid', 'name']):
                if proc.info['name'] == 'telegraf':
                    os.kill(proc.info['pid'], signal.SIGHUP)
                    logger.info("Telegraf reloaded successfully")
                    return True
            logger.warning("Telegraf process not found")
            return False
        except Exception as e:
            logger.error(f"Error reloading Telegraf: {e}")
            return False

    def add_agent(self):
        """Add a new SNMP agent"""
        while True:
            sites = self.list_sites()

            # Handle case when no sites exist
            if not sites:
                logger.info("No sites available")
                if not self._prompt_yes_no("Do you want to add a new site?"):
                    return
                site_name = input("New site name: ").strip()
                site = self.create_new_site(site_name)
                if not site:
                    return
            else:
                # Display existing sites
                print("\nSelect a site or enter a new name:")
                for i, site in enumerate(sites):
                    print(f"{i + 1}. {site}")
                print(f"{len(sites) + 1}. Add new site")

                site_input = input("Choose a number or enter a name: ").strip()

                if site_input.isdigit():
                    index = int(site_input) - 1
                    if 0 <= index < len(sites):
                        site = sites[index]
                    elif index == len(sites):
                        site_name = input("New site name: ").strip()
                        site = self.create_new_site(site_name)
                        if not site:
                            return
                    else:
                        print("Invalid option")
                        continue
                else:
                    site_lower = site_input.lower()
                    if site_lower in [s.lower() for s in sites]:
                        site = sites[[s.lower() for s in sites].index(site_lower)]
                    else:
                        site = self.create_new_site(site_input)
                        if not site:
                            return

            # Get agent IPs
            ips_input = input("Enter SNMP agent IPs (comma-separated): ").strip()
            agent_ips = [ip.strip() for ip in ips_input.split(',') if ip.strip()]

            if not agent_ips:
                print("No valid IPs entered")
                continue

            # Process each IP
            for agent_ip in agent_ips:
                if not self._is_valid_ip(agent_ip):
                    logger.error(f"Invalid IP: {agent_ip}")
                    continue

                # Try to get hostname via SNMP
                hostname = self.snmp_get(agent_ip, "1.3.6.1.2.1.1.5.0")
                if hostname:
                    logger.info(f"Hostname: {hostname}")
                else:
                    logger.warning("Could not obtain hostname")
                    hostname = None

                # Get device alias
                device_alias = input(f"Enter device alias (suggestion: {hostname if hostname else 'UNKNOWN'}): ").strip()
                device_alias = device_alias or (hostname if hostname else "UNKNOWN")

                # Apply IP inclusion in alias if configured
                if self.config['include_ip_in_alias']:
                    device_alias_all = f"{device_alias}: {agent_ip}"
                else:
                    device_alias_all = device_alias

                # Choose monitoring mode
                while True:
                    print("\n1. Monitor all interfaces")
                    print("2. Choose specific interfaces")
                    choice = input("Choose an option (1 or 2): ").strip()

                    if choice == '1':
                        # All interfaces
                        config_content = self.generate_all_interfaces_config(
                            agent_ip, device_alias_all, site
                        )
                        break
                    elif choice == '2':
                        # Selected interfaces
                        interfaces = self.get_interfaces(agent_ip)
                        if not interfaces:
                            logger.error("Could not retrieve interfaces")
                            continue

                        print("\nAvailable interfaces:")
                        for i, (if_index, if_descr) in enumerate(interfaces):
                            print(f"{i+1}. {if_descr} (Index: {if_index})")

                        selected_indices = input("Enter interface numbers (space-separated): ").strip()
                        selected_indices = [int(s) for s in selected_indices.split() if s.isdigit()]

                        selected_interfaces = []
                        for idx in selected_indices:
                            if 1 <= idx <= len(interfaces):
                                if_index, if_descr = interfaces[idx-1]
                                # Sugerimos if_descr como valor por defecto, pero solo para mostrar en el prompt
                                alias = input(f"Enter alias for interface '{if_descr}' (blank for '{if_descr}'): ").strip()
                                # Si no hay entrada, usamos if_descr como alias de la interfaz
                                interface_alias = alias if alias else if_descr
                                # Pero seguimos usando device_alias para la etiqueta device_alias
                                selected_interfaces.append((if_index, if_descr, device_alias))
                            else:
                                logger.warning(f"Invalid interface number: {idx}")

                        if not selected_interfaces:
                            logger.error("No valid interfaces selected")
                            continue

                        config_content = self.generate_selected_interfaces_config(
                            agent_ip, site, selected_interfaces
                        )
                        break
                    else:
                        print("Invalid option")

                # Generate ICMP config - Ahora pasa el nombre del sitio para el tag location
                icmp_content = self.generate_icmp_config(agent_ip, device_alias_all, site)

                # Save configurations
                config_path = os.path.join(self.config['telegraf_dir'], site, f"snmp_{agent_ip}.conf")
                icmp_path = os.path.join(self.config['telegraf_dir'], site, f"icmp_{agent_ip}.conf")

                # Check if files exist
                if os.path.exists(config_path) or os.path.exists(icmp_path):
                    if not self._prompt_yes_no("Files already exist. Overwrite?"):
                        continue

                # Write configurations
                try:
                    # Create site directory if it doesn't exist
                    site_dir = os.path.dirname(config_path)
                    if not os.path.exists(site_dir):
                        os.makedirs(site_dir)
                        self._set_proper_permissions(site_dir, is_directory=True)

                    with open(config_path, 'w') as f:
                        f.write(config_content)
                    self._set_proper_permissions(config_path)
                    logger.info(f"SNMP configuration saved to {config_path} with permissions 644 for telegraf:telegraf")

                    with open(icmp_path, 'w') as f:
                        f.write(icmp_content)
                    self._set_proper_permissions(icmp_path)
                    logger.info(f"ICMP configuration saved to {icmp_path} with permissions 644 for telegraf:telegraf")
                except IOError as e:
                    logger.error(f"Error writing files: {e}")
                    continue

            # Reload Telegraf after adding all agents
            self.reload_telegraf()
            logger.info("Agents added successfully")
            break

    def delete_agent(self):
        """Delete an SNMP agent configuration and remove data from InfluxDB"""
        sites = self.list_sites()

        if not sites:
            logger.info("No sites available")
            return

        # Select site
        print("\nSelect a site:")
        for i, site in enumerate(sites):
            print(f"{i + 1}. {site}")

        site_input = input("Choose a number or enter a name: ").strip()

        if site_input.isdigit():
            index = int(site_input) - 1
            if 0 <= index < len(sites):
                site = sites[index]
            else:
                logger.error("Invalid option")
                return
        else:
            site_lower = site_input.lower()
            if site_lower in [s.lower() for s in sites]:
                site = sites[[s.lower() for s in sites].index(site_lower)]
            else:
                logger.error("Site not found")
                return

        # Get agent IP
        agent_ip = input("IP of agent to delete: ").strip()
        if not self._is_valid_ip(agent_ip):
            logger.error("Invalid IP")
            return

        # Find and delete configuration files
        config_path = os.path.join(self.config['telegraf_dir'], site, f"snmp_{agent_ip}.conf")
        icmp_path = os.path.join(self.config['telegraf_dir'], site, f"icmp_{agent_ip}.conf")

        # Determine the actual measurement name from the config file
        measurement_name = site  # Default to site name
        try:
            if os.path.exists(config_path):
                with open(config_path, 'r') as f:
                    config_content = f.read()
                    # Look for the measurement name in the config
                    name_match = re.search(r'name\s*=\s*"([^"]+)"', config_content)
                    if name_match:
                        measurement_name = name_match.group(1)
                        logger.debug(f"Found measurement name in config: {measurement_name}")
        except Exception as e:
            logger.error(f"Error reading config to determine measurement name: {e}")

        files_deleted = []
        for path in [config_path, icmp_path]:
            if os.path.exists(path):
                if self._prompt_yes_no(f"Delete {path}?"):
                    try:
                        os.remove(path)
                        files_deleted.append(path)
                        logger.info(f"Deleted: {path}")
                    except IOError as e:
                        logger.error(f"Error deleting {path}: {e}")

        if files_deleted:
            self.reload_telegraf()
            logger.info("Agent configuration deleted")

            # Ask if user wants to delete data from InfluxDB
            if self._prompt_yes_no("Delete agent data from InfluxDB?"):
                try:
                    # Build the InfluxDB query using the correct measurement name
                    influx_query = f'DELETE FROM "{measurement_name}" WHERE "source" = \'{agent_ip}\''
                    logger.debug(f"InfluxDB query: {influx_query}")

                    # Execute the command
                    import subprocess
                    cmd = ['influx', '-username', 'telegraf',
                           '-password', 'j4l4B1n2011*',
                           '-database', 'telegraf',
                           '-execute', influx_query]

                    result = subprocess.run(cmd, capture_output=True, text=True)

                    if result.returncode == 0:
                        logger.info(f"Successfully deleted agent data from InfluxDB")
                        if result.stdout:
                            logger.debug(f"InfluxDB output: {result.stdout}")
                    else:
                        logger.error(f"Error deleting data from InfluxDB: {result.stderr}")
                except Exception as e:
                    logger.error(f"Exception when deleting from InfluxDB: {e}")

            logger.info("Agent deletion completed")
        else:
            logger.info("No files found to delete")


def create_default_config(config_path):
    """Create a default configuration file"""
    config = configparser.ConfigParser()
    config['TelegrafManager'] = {
        'telegraf_dir': '/etc/telegraf/telegraf.d',
        'include_ip_in_alias': 'false',
        'snmp_community': 'GestionGrp',
        'snmp_version': '2',
        'snmp_timeout': '5',
        'snmp_retries': '1',
        'polling_interval': '30s'
    }

    # Create the file with proper permissions
    with open(config_path, 'w') as f:
        config.write(f)
    
    try:
        # Get telegraf user and group IDs
        telegraf_uid = pwd.getpwnam('telegraf').pw_uid
        telegraf_gid = grp.getgrnam('telegraf').gr_gid
        
        # Set proper permissions and ownership
        os.chmod(config_path, 0o644)  # rw-r--r--
        os.chown(config_path, telegraf_uid, telegraf_gid)
        
        logger.info(f"Default configuration created at {config_path} with permissions 644 for telegraf:telegraf")
    except KeyError:
        logger.warning("Telegraf user or group not found. Configuration file created, but with default permissions.")
        logger.info(f"Default configuration created at {config_path}")
    except Exception as e:
        logger.warning(f"Could not set proper permissions on config file: {e}")
        logger.info(f"Default configuration created at {config_path}")

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Telegraf SNMP Management Tool')
    parser.add_argument('--config', help='Path to configuration file')
    parser.add_argument('--create-config', help='Create a default configuration file at specified path')
    parser.add_argument('--debug', action='store_true', help='Enable debug logging')

    return parser.parse_args()

def main():
    """Main function"""
    # Parse arguments
    args = parse_arguments()

    # Set debug logging if requested
    if args.debug:
        logger.setLevel(logging.DEBUG)

    # Create default config if requested
    if args.create_config:
        create_default_config(args.create_config)
        return

    # Check if running as root
    if os.geteuid() != 0:
        logger.error("This script must be run with sudo")
        sys.exit(1)

    # Initialize manager
    manager = TelegrafManager(args.config)

    # Main menu
    while True:
        print("\n--- Telegraf Management ---")
        print("1. Add agent")
        print("2. Delete agent")
        print("3. Exit")

        choice = input("Choose an option: ").strip()

        if choice == '1':
            manager.add_agent()
        elif choice == '2':
            manager.delete_agent()
        elif choice == '3':
            logger.info("Exiting...")
            break
        else:
            print("Invalid option")

if __name__ == "__main__":
    main()
