# 🔒 Rsync Jail

**A minimal chroot jail based rsync server container over SSH**

[![Docker Image](https://img.shields.io/badge/Docker-ghcr.io%2Fkristianvld%2Frsync--ssh-blue?logo=docker)](https://github.com/kristianvld/rsync-jail/pkgs/container/rsync-jail)
[![Build Status](https://img.shields.io/github/actions/workflow/status/kristianvld/rsync-jail/build-image.yml?branch=main&logo=github)](https://github.com/kristianvld/rsync-jail/actions)
[![Image Size](https://img.shields.io/badge/dynamic/json?url=https://github.com/kristianvld/rsync-jail/releases/latest/download/metadata.json&query=$.image_size_mb&label=Size&color=brightgreen&suffix=MB&logo=docker)](https://github.com/kristianvld/rsync-jail/pkgs/container/rsync-jail)
[![Alpine](https://img.shields.io/badge/dynamic/json?url=https://github.com/kristianvld/rsync-jail/releases/latest/download/metadata.json&query=$.alpine&label=Alpine&color=0D597F&logo=alpinelinux)](https://alpinelinux.org/)
[![OpenSSH](https://img.shields.io/badge/dynamic/json?url=https://github.com/kristianvld/rsync-jail/releases/latest/download/metadata.json&query=$.openssh&label=OpenSSH&color=orange&logo=openssh)](https://www.openssh.com/)
[![Rsync](https://img.shields.io/badge/dynamic/json?url=https://github.com/kristianvld/rsync-jail/releases/latest/download/metadata.json&query=$.rsync&label=Rsync&color=blue&logo=rsync)](https://rsync.samba.org/)

## 📋 Table of Contents

- [🎯 What is Rsync Jail?](#-what-is-rsync-jail)
- [✨ Key Features](#-key-features)
- [🚀 Quick Start](#-quick-start)
  - [1. Using Docker Compose (Recommended)](#1-using-docker-compose-recommended)
- [💾 Volume Mapping](#-volume-mapping)
- [📜 Pre-startup Script](#-pre-startup-script)
- [📁 File system structure](#-file-system-structure)
- [📝 Environment Variables](#-environment-variables)
- [📁 Volume Configuration](#-volume-configuration)
  - [Volume Options](#volume-options)
- [🏗️ Building from Source](#️-building-from-source)
- [🤝 Contributing](#-contributing)
- [📝 License](#-license)
- [🔗 Links](#-links)

## 🎯 What is Rsync Jail?

Rsync Jail is a **minimal** Docker container to provide an `rsync` server over SSH. It allows for easy user configuration where each user is put into their own chroot jail, with only access to the bare minimum `sh` and `rsync` binary. Designed for easy mounting of persistent data volumes and strong user segregation, even if the data volumes do not support file permissions for access control management (such as certain external pure data storage solutions). SFTP can optionally be enabled.

This container allow arbitrary `rsync` commands to be executed by the user, meaning they are able to both read and write data. For environments where even stronger limitations are required, consider using a normal OpenSSH server with `ForceCommand` to force a specific server side execution of `rsync` to be executed.

## ✨ Key Features

- **Chroot isolation** - Users are chrooted into `/home/<username>/jail/`. Only `sh` and `rsync` are available and `/home/<username>/jail/data/` is their home directory for persistent storage.
- **Simple User Definitions** - Define users as simple pairs of username and SSH public key(s)
- **SFTP** - Optionally enable SFTP
- **Minimal** - Alpine based, only 19MB in size
- **Disabled forwarding** - No TCP, agent, or X11 forwarding allowed
- **Daily Updates** - Daily builds are automatically created to catch security updates and package updates
- **Arm and AMD64** - Builds for both `linux/amd64` and `linux/arm64` architectures available

## 🚀 Quick Start

### 1. Using Docker Compose (Recommended)

Users are defined in the `/users.json` file in the following format:
```json
{
    "client1": {
        "uid": 1000,
        "keys": [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA...",
            "ssh-rsa AAAAC3NzaC1lZDI1NTE5AAAAIB..."
        ]
    },
    "client2$": {
        "uid": 1001,
        "keys": [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC..."
        ]
    },
    "client.3": {
        "uid": 1001,
        "keys": [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE...",
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF..."
        ]
    },
    "client-4": {
        "keys": [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG..."
        ]
    }
}
```

Here 4 users are defined using the usernames `client1`, `client2$`, `client.3` and `client-4`. Users may have an optional `uid` key to define the numerical UID of the users. Multiple users may use the same UID, and due to the use of chroot, users with the same uid will still not have access to each other's data directories. Users may even be given UID of `0` (`root`) if desired, which may be required for rsync to set correct permissions during transfer, but should not pose any security issue due to the chroot isolation. If no `uid` key is provided, the user id will be assigned a new unused UID.

Users may have multiple SSH public keys, which will be added to the user's authorized keys file. If no `keys` key is provided, the user will not be able to login.

> **‼️ Understanding Data Paths**
>
> Each user operates within a chroot jail where their view of the filesystem is restricted:
>
> - **Container path**: `/home/<username>/jail/data/` (actual location in container)
> - **User's view**: `/data/` (what the user sees inside their chroot jail)
> - **Home directory**: Set to `/data/` for convenience
>
> **Rsync Examples:**
>
> ```bash
> # These commands are equivalent and both access /home/client1/jail/data/my-files/
> rsync -avz client1@fileserver:my-files/ ./my-files/        # Relative to home (/data/)
> rsync -avz client1@fileserver:/data/my-files/ ./my-files/  # Absolute path within jail
> ```

**WARNING**: Be wary of special characters in the username that may upset commands such as `adduser`, `passwd` or `mkdir`. `/` especially will cause problems.

```yaml
services:
  rsync-jail:
    image: ghcr.io/kristianvld/rsync-jail:latest
    ports:
      - "2222:22"
    environment:
      - SFTP=1   # enable SFTP (optional)
      - DEBUG=1  # enable debug mode (optional)
    volumes:
      - ./ssh-keys:/etc/ssh/ssh_host_keys/       # volume for persistent SSH host keys between container restarts
      - ./users.json:/users.json:ro              # user definitions file
      - ./backup-data:/home/backup/jail/data     # example persistent read-write storage for the backup user
      - ./client-data:/home/client/jail/data:ro  # example persistent read-only storage for the client user
      - ./pre-startup.sh:/pre-startup.sh:ro      # mount a pre-startup script for extra customization (optional)
    restart: unless-stopped
    network_mode: none  # Disable outgoing network access to prevent network pivoting using the rsync command on the server
```

### 2. Configure `~/.ssh/config` (optional)

Example addition to `~/.ssh/config` to allow for easy connection to the server:

```
Host fileserver
    HostName fileserver.example.com
    User backup
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

### 3. Reading and writing files using `rsync`

```bash
rsync -avz ./local-files/ fileserver:
rsync -avz fileserver: ./restored-files/
```

## 📋 Configuration

### 🔑 User Management

Define users using environment variables with the pattern `USER_<username>=<ssh_public_key>`:

```bash
# Single key per user
USER_alice=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... alice@laptop

# Multiple keys per user (newline separated)
USER_bob=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... bob@laptop\nssh-rsa AAAAB3NzaC1yc2EAAAA... bob@desktop
```

By default user ids are defined in order of appearance, meaning `alice` will have id `1000` and `bob` will have id `1001`. However, this can be overridden by setting the `UID_<username>=<id>` environment variable, e.g:

```bash
UID_alice=1003
UID_bob=1003
```

This way, both alice and bob will have the uid `1003`.

Due to the use of chroot, users with the same uid will still not have access to each other's data directories.

### 💾 Volume Mapping

Each user gets their own isolated data directory:

```yaml
volumes:
  # Maps host directory to user's /data folder in jail
  - ./user1-data:/home/user1/jail/data # read-write volume mapping
  - ./user2-data:/home/user2/jail/data:ro # read-only volume mapping

  # Persistent SSH host keys (optional but recommended)
  - ./ssh-keys:/etc/ssh/ssh_host_keys/
```

On startup, the container sets `username:username` as the owner of the `/home/<username>/jail/data/` directory. No recursive chown is performed.

### 📜 Pre-startup Script

During startup, the script `/pre-startup.sh` is executed if it exists. The script is executed as the last before starting the SSH server, after user creating, configuring the SSH server and generating SSH host keys. If the script exists with a non-zero exit code, the container will exit and not start the SSH server.

### 📁 File system structure

```
/home/<username>/jail/              # User sees this as / after SSHing into the container
├── bin/
│   └── sh                          # sh binary
├── usr/
│   ├── bin/
│   │   └── rsync                   # rsync binary
│   └── lib/                        # Essential libraries for rsync
│       ├── libacl.so.1             # Access control list support (rsync)
│       ├── liblz4.so.1             # LZ4 compression (rsync)
│       ├── libpopt.so.0            # Command line option parsing (rsync)
│       ├── libxxhash.so.0          # xxHash hashing algorithm (rsync)
│       ├── libz.so.1               # Zlib compression (rsync)
│       └── libzstd.so.1            # Zstandard compression
├── lib/
│   └── ld-musl-aarch64.so.1        # Dynamic linker (rsync and sh) [arm64 only]
│   └── ld-musl-x86_64.so.1         # Dynamic linker (rsync and sh) [amd64 only]
└── data/                           # User's home directory and persistent data storage
```

## 📝 Environment Variables

| Variable          | Description                                                                                                       | Required | Example                                               |
| ----------------- | ----------------------------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------- |
| `DEBUG`           | Enable debug logging and verbose output.                                                                          | No       | `DEBUG=1`                                             |
| `SFTP`            | Enable SFTP subsystem in addition to `rsync`.                                                                     | No       | `SFTP=1`                                              |

## 📁 Volume Configuration

| Volume Path                  | Description                                                                         | Required | Example                              |
| ---------------------------- | ----------------------------------------------------------------------------------- | -------- | ------------------------------------ |
| `/users.json`                | User definitions file.                                                                 | Yes      | `./users.json:/users.json:ro`        |
| `/home/<username>/jail/data` | User's data directory. Maps to `/data/` inside the chroot jail.                     | Yes      | `./user1-data:/home/user1/jail/data` |
| `/etc/ssh/ssh_host_keys/`    | Persistent SSH host keys directory. Prevents host key changes on container restart. | No       | `./ssh-keys:/etc/ssh/ssh_host_keys/` |
| `/pre-startup.sh`            | Optional startup script executed before SSH server starts. Must be executable.      | No       | `./my-script.sh:/pre-startup.sh`     |

### 📂 Volume Options

- **Read-only**: Add `:ro` suffix to make volume read-only (e.g., `./data:/home/user/jail/data:ro`)
- **Ownership**: Container automatically sets `username:username` ownership on `/home/<username>/jail/data/` at startup
  - **No recursive chown**: Only the mount point ownership is changed, not existing files. Any file permissions within the data directory will have to be set or updated manually. This can be used to limit access to data in the data directory.
- **Startup Script**: If `/pre-startup.sh` exists, it's executed as the final step before starting SSH server. Non-zero exit codes will prevent container startup.

## 🏗️ Building from Source

```bash
git clone https://github.com/kristianvld/rsync-jail.git
cd rsync-jail
docker build -t rsync-jail .
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change. Feature requests and bug reports are welcome to be reported as issues.

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [GitHub Container Registry](https://github.com/kristianvld/rsync-jail/pkgs/container/rsync-jail)
- [GitHub Repository](https://github.com/kristianvld/rsync-jail)
- [Report Issues](https://github.com/kristianvld/rsync-jail/issues)
