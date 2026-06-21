#!/bin/sh

set -eu

warn() {
    printf '%s\n' "$*" >&2
}

die() {
    warn "ERROR: $*"
    exit 1
}

enabled() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

configure_filter_table() {
    firewall_cmd="$1"

    "$firewall_cmd" -w -P INPUT DROP
    "$firewall_cmd" -w -P OUTPUT DROP
    "$firewall_cmd" -w -P FORWARD DROP
    "$firewall_cmd" -w -A INPUT -i lo -j ACCEPT
    "$firewall_cmd" -w -A OUTPUT -o lo -j ACCEPT
    "$firewall_cmd" -w -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    "$firewall_cmd" -w -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    "$firewall_cmd" -w -A INPUT -p tcp --dport 22 -j ACCEPT
}

configure_network_firewall() {
    if enabled "${DISABLE_NETWORK_FIREWALL:-}" || enabled "${DISABLE_EGRESS_FIREWALL:-}"; then
        warn "[WARNING] Network filtering is disabled by DISABLE_NETWORK_FIREWALL."
        return
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        die "iptables is unavailable; install iptables or set DISABLE_NETWORK_FIREWALL=1 if filtering is controlled elsewhere."
    fi

    if ! iptables -w -L >/dev/null 2>&1; then
        die "cannot configure iptables. Start the container with NET_ADMIN or set DISABLE_NETWORK_FIREWALL=1 if filtering is controlled elsewhere."
    fi

    configure_filter_table iptables

    if command -v ip6tables >/dev/null 2>&1 && ip6tables -w -L >/dev/null 2>&1; then
        configure_filter_table ip6tables
    elif enabled "${ALLOW_IPV6_FIREWALL_FAILURE:-}"; then
        warn "[WARNING] IPv6 firewall rules were not installed. Continuing because ALLOW_IPV6_FIREWALL_FAILURE is set."
    else
        die "cannot configure ip6tables. Disable IPv6/filter it externally and set ALLOW_IPV6_FIREWALL_FAILURE=1, or fix IPv6 firewall support."
    fi
}

validate_users_file() {
    jq -e '
      type == "object"
      and all(keys[]; test("^[a-z_][a-z0-9_-]{0,31}$"))
      and all(.[]; (
        type == "object"
        and ((has("uid") | not) or (.uid | type == "number" and . == floor and . > 0 and . <= 2147483647))
        and ((has("keys") | not) or (.keys | type == "array" and all(.[]; type == "string" and length > 0)))
      ))
    ' /users.json >/dev/null || die "/users.json must be an object keyed by safe usernames, with optional positive numeric uid and string keys array."
}

if [ -n "${DEBUG:-}" ]; then
    set -x
    # Enable debug logging in sshd_config
    sed -i 's/^LogLevel VERBOSE/LogLevel DEBUG/' /etc/ssh/sshd_config
fi

configure_network_firewall

if [ -n "${SFTP:-}" ]; then
    # Enable SFTP in sshd_config
    echo "Enabling SFTP..."
    echo "Subsystem       sftp    internal-sftp" >> /etc/ssh/sshd_config
fi

if [ ! -f /users.json ]; then
    die "missing /users.json file. No users defined."
fi

validate_users_file

echo "Creating users..."
count=0
for username in $(jq -r 'keys[]' /users.json); do
    uid=$(jq -r --arg username "$username" '.[$username].uid // empty' /users.json)

    # -D: Don't assign password, -H: Don't create home directory
    # -h: Set home directory path (inside chroot), -s: set shell (inside chroot)
    # -u: Set user id
    if [ -n "$uid" ]; then
        adduser -D -H -h "/data" -s "/bin/sh" -u "$uid" "$username"
    else
        adduser -D -H -h "/data" -s "/bin/sh" "$username"
    fi
    # When no password is set, the user is by default locked. -d unlocks the user.
    # Without a password defined, it is not possible to login over password auth.
    # Password auth is also disabled in the sshd_config file.
    passwd -d "$username" >/dev/null 2>&1

    install -d -m 755 -o root -g root "/home/$username"
    install -d -m 700 -o root -g root "/home/$username/.ssh"
    jq -r --arg username "$username" '.[$username].keys[]?' /users.json > "/home/$username/.ssh/authorized_keys"
    chown root:root "/home/$username/.ssh/authorized_keys"
    chmod 600 "/home/$username/.ssh/authorized_keys"

    install -d -m 755 -o root -g root "/home/$username/jail"
    cp -a "/jail/." "/home/$username/jail/"
    chown root:root "/home/$username/jail"
    chmod 755 "/home/$username/jail"
    mkdir -p "/home/$username/jail/data/"
    chown "$username:$username" "/home/$username/jail/data/" || true

    echo "Created user $username"
    count=$((count + 1))
done

echo
echo "Done creating $count users. Starting sshd server..."
echo
if [ -n "${DEBUG:-}" ]; then
    echo "SSH configuration:"
    echo "--------------------------------"
    cat /etc/ssh/sshd_config
    echo "--------------------------------"
    echo
fi

# Generate SSH host keys if missing
# Use custom key directory /etc/ssh/ssh_host_keys/ to allow volume mounting and persistent host keys.
install -d -m 700 -o root -g root /etc/ssh/ssh_host_keys

keyfile=/etc/ssh/ssh_host_keys/ssh_host_rsa_key
if [ ! -f "$keyfile" ]; then
    echo "Generating missing SSH host key file: $keyfile"
    ssh-keygen -t rsa -b 4096 -f "$keyfile" -N ''
    chmod 600 "$keyfile"
else
    echo "SSH host key OK: $keyfile"
fi

keyfile=/etc/ssh/ssh_host_keys/ssh_host_ed25519_key
if [ ! -f "$keyfile" ]; then
    echo "Generating missing SSH host key file: $keyfile"
    ssh-keygen -t ed25519 -f "$keyfile" -N ''
    chmod 600 "$keyfile"
else
    echo "SSH host key OK: $keyfile"
fi

# Execute pre-startup script if it exists
if [ -f "/pre-startup.sh" ]; then
    echo "Executing pre-startup script..."
    /bin/sh /pre-startup.sh
    echo "Pre-startup script completed."
fi



# Start SSH daemon (-D foreground, -e log to stderr)
exec /usr/sbin/sshd -D -e 2>&1
