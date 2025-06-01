#!/bin/sh

set -e
if [ -n "$DEBUG" ]; then
    set -x
    # Enable debug logging in sshd_config
    sed -i 's/^LogLevel VERBOSE/LogLevel DEBUG/' /etc/ssh/sshd_config
fi

if [ -n "$SFTP" ]; then
    # Enable SFTP in sshd_config
    echo "Enabling SFTP..."
    echo "Subsystem       sftp    internal-sftp" >> /etc/ssh/sshd_config
fi

echo "Creating users..."
count=0
for var in $(env | grep '^USER_' | cut -d= -f1); do
    username=$(echo "$var" | sed 's/^USER_//')
    key=$(eval echo "\$USER_$username")
    uid=$(eval echo "\$UID_$username")

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
    passwd -d "$username" 2>&1 > /dev/null

    mkdir -p "/home/$username/.ssh/"
    echo -e "$key" > "/home/$username/.ssh/authorized_keys"
    cp -a "/jail/" "/home/$username/"
    mkdir -p "/home/$username/jail/data/"
    chown "$username:$username" "/home/$username/jail/data/" || true

    echo "Created user $username"
    count=$((count + 1))
done

echo
echo "Done creating $count users. Starting sshd server..."
echo
if [ -n "$DEBUG" ]; then
    echo "SSH configuration:"
    echo "--------------------------------"
    cat /etc/ssh/sshd_config
    echo "--------------------------------"
    echo
fi

# Generate SSH host keys if missing
# Use custom key directory /etc/ssh/ssh_host_keys/ to allow volume mounting and persistent host keys.
keyfile=/etc/ssh/ssh_host_keys/ssh_host_rsa_key
if [ ! -f "$keyfile" ]; then
    echo "Generating missing SSH host key file: $keyfile"
    ssh-keygen -t rsa -b 4096 -f "$keyfile" -N ''
else
    echo "SSH host key OK: $keyfile"
fi

keyfile=/etc/ssh/ssh_host_keys/ssh_host_ed25519_key
if [ ! -f "$keyfile" ]; then
    echo "Generating missing SSH host key file: $keyfile"
    ssh-keygen -t ed25519 -b 521 -f "$keyfile" -N ''
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