# install-nvm

Project philosophy — see [MOTIVATION.md](MOTIVATION.md).

A script for installing and uninstalling **NVM (Node Version Manager)** on
Ubuntu/Debian with logging, checks, a manifest, and a full lifecycle.

---

## Features

- ✅ Installs NVM from the official source
- ✅ Installs Node.js LTS via NVM
- ✅ Logs all actions
- ✅ Pre-install checks (conflicts, dependencies, disk space, internet)
- ✅ Manifest — records everything created
- ✅ **Uninstall by manifest — removes only what the project created**
- ✅ Backups of `~/.bashrc` and `~/.npmrc`
- ✅ Flags `--force`, `--dry-run`, `--keep-node`, `--keep-bashrc`, `--purge`
- ✅ Verification after install and after uninstall
- ✅ **Docker support — isolated Ubuntu 24.04 container for testing and demo**

---

## Requirements

- Ubuntu 20.04+ / Debian 11+
- `bash` >= 4.0
- `curl`, `git`
- Access to `github.com`
- Free disk space: at least 500 MB
- **Optional:** Docker 20.10+ (for containerized run — see [Docker](#docker))

---

## Project Structure

```
install-nvm/
├── install-nvm.sh           # entry point: install
├── uninstall-nvm.sh         # entry point: uninstall
├── create-snapshot.sh       # utility: create manifest manually
├── Dockerfile               # container image definition
├── .dockerignore            # files excluded from the image
├── README.md                # base documentation
├── MOTIVATION.md            # project philosophy
├── config/
│   └── nvm.conf             # variables and settings
├── lib/
│   ├── logger.sh            # logging
│   ├── manifest.sh          # manifest handling
│   ├── checks.sh            # pre-install checks
│   ├── installer.sh         # NVM and Node.js installation
│   └── uninstaller.sh       # uninstall by manifest
├── logs/                    # logs (created automatically)
└── tests/
    ├── verify.sh            # post-install verification
    └── verify-uninstall.sh  # post-uninstall verification
```

---

## Installation

### 1. Clone or copy the project

```bash
git clone <url> install-nvm
cd install-nvm
```

### 2. Make scripts executable

```bash
chmod +x install-nvm.sh
chmod +x uninstall-nvm.sh
chmod +x create-snapshot.sh
chmod +x lib/*.sh
chmod +x tests/*.sh
```

### 3. Run the installer

```bash
./install-nvm.sh
```

---

## Uninstall

### 1. Standard uninstall (with confirmation)

```bash
./uninstall-nvm.sh
```

The script:

1. Checks the manifest.
2. Shows the uninstall plan.
3. Asks for confirmation.
4. Removes only what is recorded in the manifest.
5. Creates backups of `~/.bashrc` and `~/.npmrc`.

### 2. Without confirmation

```bash
./uninstall-nvm.sh --yes
```

### 3. Show plan without uninstalling

```bash
./uninstall-nvm.sh --dry-run
```

### 4. Keep Node.js versions

```bash
./uninstall-nvm.sh --keep-node
```

Removes NVM but keeps `~/.nvm/versions/node/` with installed versions.

### 5. Leave ~/.bashrc untouched

```bash
./uninstall-nvm.sh --keep-bashrc
```

### 6. Full cleanup

```bash
./uninstall-nvm.sh --purge --yes
```

Removes everything, including `~/.npm-global` and project logs.

---

## Options

### install-nvm.sh

| Option | Description |
|---|---|
| `--help`, `-h` | Show help |
| `--debug` | Enable debug output |
| `--dry-run` | Run checks only |
| `--force` | Reinstall NVM even if it exists |

### uninstall-nvm.sh

| Option | Description |
|---|---|
| `--help`, `-h` | Show help |
| `--debug` | Enable debug output |
| `--dry-run` | Show plan without uninstalling |
| `--yes`, `-y` | Skip confirmation |
| `--keep-node` | Keep Node.js versions |
| `--keep-bashrc` | Leave `~/.bashrc` untouched |
| `--purge` | Remove `~/.npm-global` and logs |

---

## Verification

### After installation

```bash
./tests/verify.sh
```

Checks:

- NVM is installed and working
- Node.js is available (>= 20)
- npm is available
- `~/.npmrc` is free of `prefix`
- `NPM_CONFIG_PREFIX` is absent
- `PATH` contains `$NVM_DIR`
- Default Node.js is set
- `~/.bashrc` contains `NVM_DIR`
- List of installed Node.js versions

### After uninstall

```bash
./tests/verify-uninstall.sh
```

Checks:

- `~/.nvm` is removed
- `nvm.sh` is removed
- Block `# >>> install-nvm >>>` is removed from `~/.bashrc`
- `NVM_DIR` is removed from `~/.bashrc`
- `NPM_CONFIG_PREFIX` is removed from `~/.bashrc`
- `prefix` is removed from `~/.npmrc`
- `nvm` is not available in a new session
- `node` is not available in a new session
- Manifest is removed
- `PATH` is free of `.nvm`
- Backups exist

### If uninstall was run with flags

```bash
./tests/verify-uninstall.sh --keep-node
./tests/verify-uninstall.sh --keep-bashrc
```

---

## Docker

Run `install-nvm` in an isolated Ubuntu 24.04 container — useful for testing,
demos, and reproducible runs without touching the host system.

### Why Docker

- **Isolation** — the container is ephemeral; nothing leaks to the host.
- **Reproducibility** — same Ubuntu 24.04, same dependencies, same result.
- **Safety** — no risk to your system's `~/.nvm`, `~/.bashrc`, or `~/.npmrc`.
- **Demo** — show the full install flow in a clean environment.

### Build

```bash
docker build -t installer-nvm:ubuntu-24.04 .
```

The image is based on `ubuntu:24.04` and includes `sudo`, `curl`, `git`,
`ca-certificates` (project dependencies).

### Run

```bash
docker run --rm installer-nvm:ubuntu-24.04
```

This runs `./install-nvm.sh --force` inside the container. The container is
removed after completion (`--rm`), so nothing persists on the host.

### Interactive mode

To enter the container and explore manually:

```bash
docker run --rm -it installer-nvm:ubuntu-24.04 bash
```

Inside the container:

```bash
./install-nvm.sh --force
source ~/.nvm/nvm.sh
nvm --version
node -v
npm -v
```

### Notes

- The container runs as `root` — intentional for a utility container that
  installs NVM system-wide inside the isolated environment.
- Nothing is mounted from the host. All changes stay inside the container.
- `tests/` are not included in the image — verification runs on the host.
- Logs are written to `/app/logs/` inside the container (ephemeral).

---

## Manifest

The manifest is a file where `install-nvm` records everything it created
or modified.

**Path:** `~/.nvm/.install-nvm-manifest`

**Format:**

```
# install-nvm manifest
# Format: TYPE|PATH|EXTRA|TIMESTAMP
# Created: 2026-09-13T10:27:52Z
#
CREATED_DIR|/home/user/.nvm|2026-09-13T10:27:52Z
CREATED_FILE|/home/user/.nvm/nvm.sh|2026-09-13T10:27:52Z
MODIFIED_FILE|/home/user/.bashrc|2026-09-13T10:27:52Z
ADDED_LINE|/home/user/.bashrc|NVM_DIR block|2026-09-13T10:27:52Z
BACKUP|/home/user/.bashrc.bak.20260913_102752|2026-09-13T10:27:52Z
PACKAGE|curl|2026-09-13T10:27:52Z
NODE_VERSION|v22.23.2|2026-09-13T10:27:52Z
```

### Record types

| TYPE | Meaning |
|---|---|
| `CREATED_DIR` | Directory created |
| `CREATED_FILE` | File created |
| `MODIFIED_FILE` | File modified |
| `ADDED_LINE` | Line added |
| `BACKUP` | Backup created |
| `PACKAGE` | System package installed |
| `NODE_VERSION` | Node.js version installed |
| `NPM_PACKAGE` | Global npm package installed |

### Why the manifest

- `uninstall-nvm` knows exactly what to remove.
- It does not remove anything else.
- You can see what was done.
- It acts as a project "receipt".

### If the manifest is lost

Use `create-snapshot.sh` to restore it:

```bash
./create-snapshot.sh --dry-run   # preview
./create-snapshot.sh             # create
```

---

## Logs

Logs are written to `logs/`:

```
logs/
├── install-2026-09-13_01-47-25.log       # from install-nvm.sh
├── install-2026-09-13_01-40-38.log       # from tests/verify.sh
└── install-2026-09-13_14-00-00.log       # from uninstall-nvm.sh
```

**Line format:**

```
[LEVEL] YYYY-MM-DD HH:MM:SS message
```

**Levels:** DEBUG, INFO, SUCCESS, WARN, ERROR.

**Configuration** — in `config/nvm.conf`:

```bash
LOG_DIR="./logs"
LOG_LEVEL="INFO"
LOG_TO_FILE=true
LOG_TO_CONSOLE=true
```

---

## How It Works

### Installation

```
install-nvm.sh
    │
    ├─ 1. Loads config/nvm.conf
    ├─ 2. Sources lib/logger.sh, manifest.sh, checks.sh, installer.sh
    ├─ 3. manifest_init() — creates the manifest
    ├─ 4. run_all_checks() — checks
    ├─ 5. run_installation()
    │       ├─ cleanup_npmrc_prefix()      → to manifest
    │       ├─ cleanup_npm_config_prefix() → to manifest
    │       ├─ install_dependencies()      → PACKAGE
    │       ├─ download_nvm_installer()
    │       ├─ run_nvm_installer()
    │       ├─ record_nvm_created()        → CREATED_*
    │       ├─ activate_nvm()
    │       ├─ verify_nvm_installation()
    │       ├─ install_node_default()      → NODE_VERSION
    │       └─ add_bashrc_block()          → MODIFIED_FILE, ADDED_LINE
    └─ 6. manifest_summary()
```

### Uninstall

```
uninstall-nvm.sh
    │
    ├─ 1. Loads config/nvm.conf
    ├─ 2. Sources lib/logger.sh, manifest.sh, checks.sh, uninstaller.sh
    ├─ 3. check_manifest_exists()
    ├─ 4. check_nvm_running()
    ├─ 5. show_uninstall_plan()
    ├─ 6. Confirmation
    ├─ 7. run_uninstallation()
    │       ├─ remove_npm_packages()
    │       ├─ clean_bashrc_block()        → removes block by markers
    │       ├─ clean_npm_config_prefix()
    │       ├─ clean_npmrc_prefix()
    │       ├─ remove_created_files()      → by manifest
    │       ├─ remove_created_dirs()       → by manifest
    │       ├─ remove_npm_global()         → only with --purge
    │       ├─ remove_manifest()
    │       ├─ remove_logs()               → only with --purge
    │       └─ verify_uninstall()
    └─ 8. show_uninstall_next_steps()
```

---

## What Is Removed and What Is Not

### Removed

| What | When |
|---|---|
| `~/.nvm/` | Always |
| Node.js versions | Always (unless `--keep-node`) |
| Global npm packages | Together with `~/.nvm` |
| install-nvm block in `~/.bashrc` | Always (unless `--keep-bashrc`) |
| `prefix` in `~/.npmrc` | If present |
| `NPM_CONFIG_PREFIX` in `~/.bashrc` | If present |
| `~/.npm-global` | Only with `--purge` |
| Project logs | Only with `--purge` |

### Not Removed

| What | Why |
|---|---|
| System packages `curl`, `git` | Needed by others |
| `~/.npmrc` (as a whole) | Only `prefix` |
| `~/.bashrc` (as a whole) | Only the install-nvm block |
| Backups | For rollback |

---

## Security

- ✅ NVM installation without `sudo`
- ✅ `sudo` only for `apt install` of dependencies
- ✅ Backups of `~/.bashrc` and `~/.npmrc` before modification
- ✅ Removal only by manifest
- ✅ Markers `# >>> install-nvm >>>` for precise cleanup
- ✅ `--dry-run` for safe preview
- ✅ Confirmation before uninstall

---

## Full Lifecycle Test

```bash
# 1. Install
./install-nvm.sh

# 2. Verify
./tests/verify.sh

# 3. Uninstall
./uninstall-nvm.sh --yes

# 4. Verify uninstall
./tests/verify-uninstall.sh

# 5. Install again
./install-nvm.sh
```

---

## Troubleshooting

### `nvm: command not found` after installation

```bash
source ~/.bashrc
```

Or open a new terminal.

### `NPM_CONFIG_PREFIX` conflicts with NVM

NVM is incompatible with `NPM_CONFIG_PREFIX`. If it is set, remove it:

```bash
unset NPM_CONFIG_PREFIX
```

And remove it from `~/.bashrc`.

### `prefix` in `~/.npmrc` conflicts with NVM

```bash
npm config delete prefix
```

### Uninstall does not remove everything

Check the manifest:

```bash
cat ~/.nvm/.install-nvm-manifest
```

If the manifest is lost, use `create-snapshot.sh`.

### `--force` does not work

Check that `FORCE` is not being overwritten in `config/nvm.conf`.

---

## Removing the Project Entirely

If you want to remove the project itself:

```bash
# 1. Remove NVM
./uninstall-nvm.sh --purge --yes

# 2. Remove the project
cd ..
rm -rf install-nvm/
```

---

## License

MIT

---

## Author

Denis Roshchupkin — DevOps freelance