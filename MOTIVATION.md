
# Why This Project

## The Problem

On the internet, almost every service requires a **login — password** pair.
There are many such pairs: email, banking, social media, work services, GitHub, AWS.

There are three ways to handle them.

### 1. Memorize

Ideal — if it worked.

In practice:
- People forget passwords.
- They use weak passwords (`123456`, `qwerty`).
- They reuse one password across different sites.
- They write them on sticky notes.

**Result:** a leak on one site → a breach on all of them.

### 2. Write Them Down

Paper, notebook, file, spreadsheet.

**Problems:**
- Risk of loss (fire, theft, accidental deletion).
- Risk of compromise (someone saw it, copied it).
- Hard to share between people, machines, or groups.
- No versioning — it is unclear which password is current.

### 3. Automate

Special programs — **password managers**.

**What they do:**
- Generate strong passwords.
- Store them encrypted.
- Sync across devices.
- Allow sharing with others.
- Fill in forms automatically.

**This is not an ideal solution. But it is the optimal one.**

---

## The Solution

**Bitwarden** was chosen — an open-source password manager.

### Why Bitwarden

| Reason | Explanation |
|---|---|
| **Open source** | You can verify how it works |
| **Free** | Core features at no cost |
| **Cross-platform** | Linux, Windows, macOS, Android, iOS |
| **CLI** | Works from the terminal |
| **Zero-knowledge** | The server does not know the master password |
| **Sync** | Across devices |
| **Sharing** | With other users |

**Bitwarden is not the only option.**
There are 1Password, LastPass, KeePass, Proton Pass.
But Bitwarden fits the task: generating, storing,
using, and sharing passwords.

---

## Why Not Just `apt install nodejs`

**Bitwarden CLI** (`bw`) is written in **Node.js**.
To run it, you need Node.js and NPM.

You can install Node.js via `apt`:

```bash
sudo apt install nodejs npm
But this is a poor option.

Problem	Explanation
Requires sudo	Root privileges for installation
One version	Cannot have multiple versions
Outdated	The apt version is older than current
Breaks the system	Conflicts with system packages
NVM solves these problems.

NVM Advantage	Explanation
No sudo	Everything lives in ~/.nvm
Multiple versions	Switch with a single command
Current versions	Downloaded from the official site
Does not break the system	Isolated in the home directory
Standard	Widely used in development
The Chain
text
install-nvm.sh  →  NVM  →  Node.js  →  NPM  →  Bitwarden CLI
Step by step:

Step	What	Why
1	install-nvm.sh	Installs NVM
2	NVM	Installs Node.js
3	Node.js	Includes NPM
4	NPM	Installs Bitwarden CLI
5	Bitwarden CLI	Manages passwords
Why this order:

NVM is needed to install Node.js without sudo.

Node.js is needed because Bitwarden CLI is written in it.

NPM is needed to install Bitwarden CLI.

Bitwarden CLI is needed to work with passwords from the terminal.

Project Scope
What This Project Does
✅ Installs NVM

✅ Installs Node.js LTS

✅ Configures NPM

✅ Prepares the environment for Bitwarden CLI

What This Project Does NOT Do
❌ Does not install Bitwarden CLI

❌ Does not configure Bitwarden

❌ Does not manage passwords

Bitwarden CLI is the next step. A separate task.

What's Next
After installing NVM, Node.js, and NPM:

bash
npm install -g @bitwarden/cli
bw --version
bw login
Then:

Configure 2FA in Bitwarden.

Save recovery codes.

Import passwords from your old manager.

Use bw to work with passwords.

Project Philosophy
This project is the first step toward automating password management.

It does not solve the problem entirely. But it builds the foundation:

Secure Node.js installation (without sudo).

A ready environment for Bitwarden CLI.

A clear lifecycle (install → uninstall).

The next steps are about Bitwarden:

Installing the CLI.

Configuring it.

Importing data.

Managing passwords.

Links
Bitwarden

Bitwarden CLI

NVM

Node.js

NPM

License
MIT

Author
Denis Roshchupkin 
