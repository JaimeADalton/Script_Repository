#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <sstream>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <regex>
#include <csignal>
#include <fcntl.h>
#include <fstream>
#include <chrono>
#include <ctime>
#include <map>
#include <stdexcept>
#include <cstring>
#include <numeric>
#include <boost/property_tree/ptree.hpp>
#include <boost/property_tree/ini_parser.hpp>
#include <sys/types.h>
#include <pwd.h>
#include <grp.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <pty.h>
#include <sys/capability.h>
#include <sys/prctl.h>
#include <linux/capability.h>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip_icmp.h>
#include <arpa/inet.h>
#include <fcntl.h>

const size_t MAX_BUFFER_SIZE = 4096;
const int DEFAULT_MAX_ARGS = 10;
const int DEFAULT_MAX_ARG_LENGTH = 100;
const int DEFAULT_COMMAND_TIMEOUT = 30;
const std::string DEFAULT_LOG_FILE = "/var/log/secure_shell.log";
const int DEFAULT_LOG_ROTATE_SIZE = 1048576; // 1MB

struct Config {
    int max_args;
    int max_arg_length;
    int command_timeout;
    std::string log_file;
    int log_rotate_size;
};

Config load_config(const std::string& config_file) {
    boost::property_tree::ptree pt;
    boost::property_tree::ini_parser::read_ini(config_file, pt);

    Config config;
    config.max_args = pt.get<int>("Settings.MaxArgs", DEFAULT_MAX_ARGS);
    config.max_arg_length = pt.get<int>("Settings.MaxArgLength", DEFAULT_MAX_ARG_LENGTH);
    config.command_timeout = pt.get<int>("Settings.CommandTimeout", DEFAULT_COMMAND_TIMEOUT);
    config.log_file = pt.get<std::string>("Settings.LogFile", DEFAULT_LOG_FILE);
    config.log_rotate_size = pt.get<int>("Settings.LogRotateSize", DEFAULT_LOG_ROTATE_SIZE);

    return config;
}

std::shared_ptr<spdlog::logger> setup_logger(const Config& config) {
    auto logger = spdlog::rotating_logger_mt("secure_shell_logger", config.log_file, config.log_rotate_size, 3);
    logger->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
    return logger;
}

std::string get_local_ip() {
    struct ifaddrs *ifaddr, *ifa;
    std::string ip;

    if (getifaddrs(&ifaddr) == -1) {
        return "Unknown";
    }

    for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr == NULL)
            continue;

        if (ifa->ifa_addr->sa_family == AF_INET) {
            struct sockaddr_in *pAddr = (struct sockaddr_in *)ifa->ifa_addr;
            if (std::string(ifa->ifa_name) != "lo") {
                ip = inet_ntoa(pAddr->sin_addr);
                break;
            }
        }
    }

    freeifaddrs(ifaddr);
    return ip.empty() ? "Unknown" : ip;
}

std::string get_ssh_client_ip() {
    const char* ssh_client = getenv("SSH_CLIENT");
    if (ssh_client) {
        std::istringstream iss(ssh_client);
        std::string ip;
        iss >> ip;
        return ip;
    }
    return "Unknown";
}

bool is_allowed_command(const std::string &command) {
    static const std::vector<std::string> allowed_commands = {"ping", "tracepath", "ssh"};
    return std::find(allowed_commands.begin(), allowed_commands.end(), command) != allowed_commands.end();
}

bool is_safe_ssh_argument(const std::string &arg) {
    static const std::vector<std::string> forbidden_options = {"-L", "-R", "-D"};
    for (const auto &option : forbidden_options) {
        if (arg.find(option) == 0) {
            return false;
        }
    }

    static const std::regex ssh_arg_regex("^(-[1246AaCfGgKkMNnqsTtVvXxYy]|-[bceiJlmOopQRSWw]\\s*\\w+|[a-zA-Z0-9._-]+@?[a-zA-Z0-9.-]+)$");
    return std::regex_match(arg, ssh_arg_regex);
}

bool is_safe_argument(const std::string &arg, const std::string &command, int max_arg_length) {
    static const std::map<std::string, std::regex> command_arg_patterns = {
        {"ping", std::regex("^(-[cwW]\\s*\\d+|-[fnqv]|\\d{1,3}(\\.\\d{1,3}){3}|[a-zA-Z0-9.-]+)$")},
        {"tracepath", std::regex("^(-[nl]\\s*\\d+|-[bfhm]|\\d{1,3}(\\.\\d{1,3}){3}|[a-zA-Z0-9.-]+)$")}
    };

    if (command == "ssh") {
        return is_safe_ssh_argument(arg) && arg.length() <= max_arg_length;
    }

    auto it = command_arg_patterns.find(command);
    if (it == command_arg_patterns.end()) {
        return false;
    }

    return std::regex_match(arg, it->second) && arg.length() <= max_arg_length;
}

std::string sanitize_input(const std::string& input) {
    std::string sanitized;
    std::copy_if(input.begin(), input.end(), std::back_inserter(sanitized),
                 [](char c) { return std::isalnum(c) || c == ' ' || c == '-' || c == '.' || c == '@' || c == '_' || c == '/'; });
    return sanitized;
}

volatile sig_atomic_t g_running = 1;
volatile pid_t g_child_pid = -1;

void signal_handler(int signum) {
    if (g_child_pid > 0) {
        kill(g_child_pid, SIGINT);
    }
}

bool check_ssh_key(const std::string& hostname, std::shared_ptr<spdlog::logger> logger) {
    std::array<char, 128> buffer;
    std::string result;
    std::string cmd = "ssh-keygen -vvv -F " + hostname + " 2>&1";  // Added verbose flag

    logger->info("Executing: {}", cmd);
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        logger->error("popen() failed for command: {}", cmd);
        throw std::runtime_error("popen() failed!");
    }

    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        result += buffer.data();
    }

    int ret_code = pclose(pipe);
    logger->info("ssh-keygen returned: {}", ret_code);
    logger->info("ssh-keygen complete output:\n{}", result);

    if (ret_code != 0) {
        return false;
    }

    return result.find("Host") != std::string::npos;
}

bool add_ssh_key(const std::string& hostname, std::shared_ptr<spdlog::logger> logger) {
    std::array<char, 128> buffer;
    std::string result;
    std::string cmd = "ssh-keyscan -vvv -H " + hostname + " 2>&1";  // Added verbose flag

    logger->info("Running ssh-keyscan for hostname: {}", hostname);
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        logger->error("popen() failed for ssh-keyscan");
        return false;
    }

    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        result += buffer.data();
    }

    int ret_code = pclose(pipe);
    if (ret_code != 0) {
        logger->error("ssh-keyscan failed with return code: {}", ret_code);
        logger->error("ssh-keyscan complete output:\n{}", result);
        return false;
    }

    if (!result.empty()) {
        std::string home_dir = std::getenv("HOME");
        if (home_dir.empty()) {
            logger->error("Unable to get HOME directory");
            return false;
        }

        std::string ssh_dir = home_dir + "/.ssh";
        std::string known_hosts_path = ssh_dir + "/known_hosts";

        logger->info("Checking if .ssh directory exists at: {}", ssh_dir);
        if (access(ssh_dir.c_str(), F_OK) == -1) {
            logger->info(".ssh directory does not exist, creating directory");
            if (mkdir(ssh_dir.c_str(), 0700) == -1) {
                logger->error("Unable to create .ssh directory: {}", strerror(errno));
                return false;
            }
        }

        logger->info("Opening known_hosts file: {}", known_hosts_path);
        std::ofstream known_hosts_file(known_hosts_path, std::ios::app);
        if (!known_hosts_file) {
            logger->error("Unable to open known_hosts file: {}", strerror(errno));
            return false;
        }

        logger->info("Writing host key to known_hosts file");
        known_hosts_file << result;
        if (!known_hosts_file) {
            logger->error("Unable to write to known_hosts file: {}", strerror(errno));
            return false;
        }

        logger->info("Successfully added host key for {}", hostname);
        return true;
    }

    logger->error("Failed to get host key for {}", hostname);
    return false;
}

bool prompt_user_for_ssh_key(const std::string& hostname) {
    std::cout << "Warning: The host key for " << hostname << " is not found or has changed." << std::endl;
    std::cout << "The authenticity of host '" << hostname << "' can't be established." << std::endl;
    std::cout << "Are you sure you want to continue connecting (yes/no)? ";
    std::string response;
    std::getline(std::cin, response);
    return response == "yes";
}

std::string extract_hostname(const std::string& ssh_arg) {
    auto at_pos = ssh_arg.find('@');
    if (at_pos != std::string::npos) {
        return ssh_arg.substr(at_pos + 1);
    }
    return ssh_arg;
}

bool is_valid_hostname(const std::string& hostname) {
    struct sockaddr_in sa;
    // Check if it's a valid IP address
    if (inet_pton(AF_INET, hostname.c_str(), &(sa.sin_addr)) == 1) {
        return true;
    }

    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    int status = getaddrinfo(hostname.c_str(), NULL, &hints, &res);
    if (status != 0) {
        return false;
    }

    freeaddrinfo(res);
    return true;
}

bool is_port_open(const std::string& hostname, int port, std::shared_ptr<spdlog::logger> logger) {
    struct addrinfo hints, *res;
    int sockfd;

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    std::string port_str = std::to_string(port);
    if (getaddrinfo(hostname.c_str(), port_str.c_str(), &hints, &res) != 0) {
        logger->error("getaddrinfo failed for host: {}", hostname);
        return false;
    }

    sockfd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (sockfd < 0) {
        logger->error("socket creation failed for host: {}", hostname);
        freeaddrinfo(res);
        return false;
    }

    // Set socket to non-blocking
    int flags = fcntl(sockfd, F_GETFL, 0);
    fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);

    int connect_result = connect(sockfd, res->ai_addr, res->ai_addrlen);
    if (connect_result < 0) {
        if (errno == EINPROGRESS) {
            fd_set fdset;
            struct timeval tv;
            FD_ZERO(&fdset);
            FD_SET(sockfd, &fdset);
            tv.tv_sec = 5;  // 5 second timeout
            tv.tv_usec = 0;

            if (select(sockfd + 1, NULL, &fdset, NULL, &tv) == 1) {
                int so_error;
                socklen_t len = sizeof so_error;
                getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &so_error, &len);
                if (so_error == 0) {
                    logger->info("Port {} is open on host: {}", port, hostname);
                    close(sockfd);
                    freeaddrinfo(res);
                    return true;
                }
            }
        }
        logger->warn("Port {} is closed on host: {}", port, hostname);
        close(sockfd);
        freeaddrinfo(res);
        return false;
    }

    logger->info("Port {} is open on host: {}", port, hostname);
    close(sockfd);
    freeaddrinfo(res);
    return true;
}

bool ping_host(const std::string& hostname, std::shared_ptr<spdlog::logger> logger) {
    std::array<char, 128> buffer;
    std::string result;
    std::string cmd = "ping -c 1 -W 5 " + hostname + " 2>&1";

    logger->info("Executing ping command: {}", cmd);
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        logger->error("popen() failed for ping command");
        return false;
    }

    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        result += buffer.data();
    }

    int ret_code = pclose(pipe);
    logger->info("ping command returned: {}", ret_code);

    if (ret_code == 0) {
        logger->info("Host {} is reachable", hostname);
        return true;
    } else {
        logger->warn("Host {} is not reachable", hostname);
        return false;
    }
}

void execute_command(const std::string &command, const std::vector<std::string> &args, const Config& config, std::shared_ptr<spdlog::logger> logger) {
    logger->info("Executing command: {} {}", command, std::accumulate(args.begin(), args.end(), std::string(),
                 [](const std::string& a, const std::string& b) { return a + (a.empty() ? "" : " ") + b; }));

    int master, slave;
    char name[MAX_BUFFER_SIZE];
    g_child_pid = forkpty(&master, name, NULL, NULL);

    if (g_child_pid == 0) {
        // Child process
        logger->info("Child process started");
        std::vector<const char*> exec_args;
        exec_args.push_back(command.c_str());
        for (const auto &arg : args) {
            exec_args.push_back(arg.c_str());
        }
        exec_args.push_back(nullptr);

        logger->info("Executing command in child process: {}", command);
        execvp(command.c_str(), const_cast<char* const*>(exec_args.data()));
        logger->error("Error executing command: {}", strerror(errno));
        exit(EXIT_FAILURE);
    } else if (g_child_pid < 0) {
        logger->error("Fork failed: {}", strerror(errno));
        throw std::runtime_error("Fork failed: " + std::string(strerror(errno)));
    } else {
        // Parent process
        logger->info("Parent process monitoring child PID: {}", g_child_pid);
        std::vector<char> buffer(MAX_BUFFER_SIZE);
        fd_set fd_in;
        struct timeval tv;
        time_t start_time = time(NULL);

        while (g_running) {
            FD_ZERO(&fd_in);
            FD_SET(master, &fd_in);
            FD_SET(STDIN_FILENO, &fd_in);

            tv.tv_sec = 1;  // Check every second
            tv.tv_usec = 0;

            int ret = select(master + 1, &fd_in, NULL, NULL, &tv);

            if (ret < 0) {
                if (errno == EINTR) continue;
                break;
            }

            if (ret == 0) {
                // Timeout occurred, check if we've exceeded the command timeout
                if (difftime(time(NULL), start_time) > config.command_timeout) {
                    kill(g_child_pid, SIGTERM);
                    logger->warn("Command timed out after {} seconds.", config.command_timeout);
                    break;
                }
                continue;
            }

            if (FD_ISSET(STDIN_FILENO, &fd_in)) {
                int bytes_read = read(STDIN_FILENO, buffer.data(), buffer.size());
                if (bytes_read <= 0) break;
                write(master, buffer.data(), bytes_read);
                logger->info("User input: {}", std::string(buffer.data(), bytes_read));
            }

            if (FD_ISSET(master, &fd_in)) {
                int bytes_read = read(master, buffer.data(), buffer.size());
                if (bytes_read <= 0) break;
                write(STDOUT_FILENO, buffer.data(), bytes_read);
                logger->info("Command output: {}", std::string(buffer.data(), bytes_read));
            }
        }

        int status;
        waitpid(g_child_pid, &status, 0);
        g_child_pid = -1;
    }
}

void drop_privileges() {
    cap_t caps;

    caps = cap_get_proc();
    if (caps == NULL) {
        throw std::runtime_error("Failed to get capabilities");
    }

    if (cap_clear(caps) == -1) {
        cap_free(caps);
        throw std::runtime_error("Failed to clear capabilities");
    }

    cap_value_t cap_list[] = {CAP_NET_RAW, CAP_NET_ADMIN};
    if (cap_set_flag(caps, CAP_EFFECTIVE, 2, cap_list, CAP_SET) == -1 ||
        cap_set_flag(caps, CAP_PERMITTED, 2, cap_list, CAP_SET) == -1) {
        cap_free(caps);
        throw std::runtime_error("Failed to set capability flags");
    }

    if (cap_set_proc(caps) == -1) {
        cap_free(caps);
        throw std::runtime_error("Failed to set capabilities");
    }

    cap_free(caps);

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == -1) {
        throw std::runtime_error("Failed to set no_new_privs");
    }
}

void set_resource_limits() {
    struct rlimit rlim;

    // Set process limit
    rlim.rlim_cur = rlim.rlim_max = 1024;
    if (setrlimit(RLIMIT_NPROC, &rlim) != 0) {
        throw std::runtime_error("Failed to set process limit: " + std::string(strerror(errno)));
    }

    // Set memory limit (e.g., 1GB)
    rlim.rlim_cur = rlim.rlim_max = 1024 * 1024 * 1024;
    if (setrlimit(RLIMIT_AS, &rlim) != 0) {
        throw std::runtime_error("Failed to set memory limit: " + std::string(strerror(errno)));
    }

    // Set CPU time limit (e.g., 60 segundos)
    rlim.rlim_cur = rlim.rlim_max = 60;
    if (setrlimit(RLIMIT_CPU, &rlim) != 0) {
        throw std::runtime_error("Failed to set CPU time limit: " + std::string(strerror(errno)));
    }
}

int main(int argc, char* argv[]) {
    try {
        std::string config_file = "/etc/secure_shell.conf";
        if (argc > 1) {
            config_file = argv[1];
        }

        Config config = load_config(config_file);
        auto logger = setup_logger(config);

        logger->info("Secure shell started with config file: {}", config_file);

        set_resource_limits();
        logger->info("Resource limits set");

        struct sigaction sa;
        sa.sa_handler = signal_handler;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = SA_RESTART;
        if (sigaction(SIGINT, &sa, nullptr) == -1 ||
            sigaction(SIGTERM, &sa, nullptr) == -1 ||
            sigaction(SIGQUIT, &sa, nullptr) == -1) {
            throw std::runtime_error("Failed to set signal handlers: " + std::string(strerror(errno)));
        }

        drop_privileges();

        logger->info("Secure shell started");

        std::string input;
        while (g_running) {
            std::cout << "secure-shell> ";
            if (!std::getline(std::cin, input)) {
                break;
            }
            logger->info("User input: {}", input);

            input = sanitize_input(input);

            if (input.empty()) continue;
            if (input == "exit") {
                logger->info("Exiting shell");
                break;
            }
            if (input.length() > config.max_arg_length * config.max_args) {
                logger->warn("Input too long");
                std::cerr << "Error: Input too long." << std::endl;
                continue;
            }

            std::istringstream iss(input);
            std::vector<std::string> tokens{std::istream_iterator<std::string>{iss}, std::istream_iterator<std::string>{}};

            if (tokens.empty()) continue;
            if (tokens.size() > config.max_args) {
                logger->warn("Too many arguments");
                std::cerr << "Error: Too many arguments." << std::endl;
                continue;
            }

            std::string command = tokens[0];
            tokens.erase(tokens.begin());

            if (!is_allowed_command(command)) {
                logger->warn("Command not allowed: {}", command);
                std::cerr << "Error: Command not allowed." << std::endl;
                continue;
            }

            if (command == "ssh") {
                std::string hostname = extract_hostname(tokens.back());
                if (!is_valid_hostname(hostname)) {
                    logger->warn("Invalid hostname or IP: {}", hostname);
                    std::cerr << "Error: Invalid hostname or IP address." << std::endl;
                    continue;
                }

                int ssh_port = 22;  // Default SSH port
                auto port_it = std::find(tokens.begin(), tokens.end(), "-p");
                if (port_it != tokens.end() && std::next(port_it) != tokens.end()) {
                    ssh_port = std::stoi(*std::next(port_it));
                }

                if (!ping_host(hostname, logger)) {
                    std::cerr << "Warning: Host " << hostname << " is not responding to ping." << std::endl;
                    std::cout << "Do you want to continue? (yes/no): ";
                    std::string response;
                    std::getline(std::cin, response);
                    if (response != "yes") {
                        logger->info("SSH connection aborted by user for non-responsive host: {}", hostname);
                        continue;
                    }
                }

                if (!is_port_open(hostname, ssh_port, logger)) {
                    std::cerr << "Warning: SSH port " << ssh_port << " is not open on host " << hostname << "." << std::endl;
                    std::cout << "Do you want to continue? (yes/no): ";
                    std::string response;
                    std::getline(std::cin, response);
                    if (response != "yes") {
                        logger->info("SSH connection aborted by user for closed port on host: {}", hostname);
                        continue;
                    }
                }

                if (!check_ssh_key(hostname, logger)) {
                    if (!prompt_user_for_ssh_key(hostname)) {
                        logger->info("SSH connection aborted by user for host: {}", hostname);
                        std::cerr << "Error: Connection aborted by the user." << std::endl;
                        continue;
                    }
                    try {
                        if (!add_ssh_key(hostname, logger)) {
                            logger->error("Unable to add SSH host key for: {}", hostname);
                            std::cerr << "Error: Unable to add the host key for " << hostname << "." << std::endl;
                            continue;
                        }
                    } catch (const std::exception& e) {
                        logger->error("Error adding SSH host key: {}", e.what());
                        std::cerr << "Error: " << e.what() << std::endl;
                        continue;
                    }
                    logger->info("Added SSH host key for: {}", hostname);
                }
            }

            bool all_args_safe = std::all_of(tokens.begin(), tokens.end(), [&command, &config](const std::string& arg) {
                return is_safe_argument(arg, command, config.max_arg_length);
            });
            if (!all_args_safe) {
                logger->warn("Invalid or unsafe arguments for command: {}", command);
                std::cerr << "Error: Invalid or unsafe arguments." << std::endl;
                continue;
            }

            logger->info("Executing command: {} {}", command,
                         std::accumulate(tokens.begin(), tokens.end(), std::string(),
                         [](const std::string& a, const std::string& b) { return a + (a.empty() ? "" : " ") + b; }));

            try {
                execute_command(command, tokens, config, logger);
            } catch (const std::exception& e) {
                logger->error("Error executing command: {}", e.what());
                std::cerr << "Error executing command: " << e.what() << std::endl;
            }
        }

        logger->info("Secure shell ended");
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
