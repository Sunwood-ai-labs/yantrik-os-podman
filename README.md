<div align="center">
  <img src="assets/logo.svg" alt="Yantrik OS Podman logo" width="96" />
  <h1>Yantrik OS Podman</h1>
  <p>Run Yantrik OS inside a KVM-accelerated Podman + QEMU container on Windows 11 + WSL2 with browser noVNC access and a complete Surface Protocol walkthrough.</p>
  <p>
    <a href="https://github.com/Sunwood-ai-labs/yantrik-os-podman/actions/workflows/ci.yml"><img src="https://github.com/Sunwood-ai-labs/yantrik-os-podman/actions/workflows/ci.yml/badge.svg" alt="Repository QA" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-10B981.svg" alt="MIT License" /></a>
    <a href="https://podman.io/"><img src="https://img.shields.io/badge/Podman-WSL2%20%2B%20KVM-892CA0.svg?logo=podman&logoColor=white" alt="Podman WSL2 + KVM" /></a>
    <a href="https://github.com/qemux/qemu"><img src="https://img.shields.io/badge/qemux%2Fqemu-UEFI-38BDF8.svg" alt="qemux/qemu UEFI" /></a>
  </p>
  <p>
    <a href="README.ja.md">日本語</a>
    ·
    <a href="#-quick-start">Quick Start</a>
    ·
    <a href="#-key-fixes-for-podman--qemuxqemu">Key Fixes</a>
    ·
    <a href="#-visual-walkthrough-35-screenshots">Screenshots</a>
    ·
    <a href="https://github.com/Sunwood-ai-labs/yantrik-os-podman/issues">Issues</a>
  </p>
</div>

## ✨ Overview

**Yantrik OS Podman** packages a ready-to-run [Podman](https://podman.io/) + [`qemux/qemu`](https://github.com/qemux/qemu) environment for booting and exploring [Yantrik OS](https://yantrikos.com/) (an agentic Linux desktop distribution built on Debian 13 with kernel `6.12.107`) on Windows 11 + WSL2.

Instead of flashing USB drives or manually configuring VirtualBox/QEMU flags, this repository automates ISO retrieval, SHA256 verification, WSL2 `/dev/kvm` nested virtualization setup, and container orchestration so the entire Yantrik OS desktop is accessible at `http://127.0.0.1:8006` in your browser.

<p align="center">
  <img src="screenshots/11-after-skip.png" alt="Yantrik OS Desktop running in Podman + QEMU" width="92%" />
</p>

## 🚀 Highlights

- **One-command Windows 11 + WSL2 launcher (`yantrik-podman.ps1`)**: Starts the WSL2 Podman machine, loads `kvm_intel` or `kvm_amd`, sets `/dev/kvm` permissions, and runs `podman compose` directly inside the Linux VM.
- **Automated Nightly ISO fetcher (`scripts/download-iso.ps1`)**: Queries `https://iso.yantrikos.com/nightly/latest.json`, downloads `yantrik.iso` with resume support, and verifies the SHA256 checksum (`v0.1.0-641-g9f675b7`).
- **Solved `qemux/qemu` v7.50 + hybrid ISO boot pitfalls**: Configured for OVMF (`BOOT_MODE: "uefi"`) and read-write USB disk pass-through (`./yantrik.iso:/boot.iso` without `:ro`).
- **Complete 35-screenshot visual tour (`screenshots/`)**: Covers the 5-step onboarding wizard, 33 native apps, AI Harnesses (`Yantrik Companion`, `DeepSeek`, `Hermes`, `OpenClaw`), 50-skill store, and programmatic GUI control via the `yos` Surface Protocol CLI.

## ⚡ Quick Start

### Prerequisites

- Windows 11 with WSL2 and nested virtualization enabled
- [Podman Desktop](https://podman-desktop.io/) or Podman CLI for Windows (`podman.exe`)
- PowerShell 5.1 or PowerShell 7+

### 1. Clone and run one-shot setup

```powershell
git clone https://github.com/Sunwood-ai-labs/yantrik-os-podman.git
Set-Location yantrik-os-podman
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 setup
```

`.\yantrik-podman.ps1 setup` performs three steps automatically:

1. Downloads the latest Yantrik OS Nightly ISO (`~1.45 GB`) to `./yantrik.iso` and verifies its SHA256 digest.
2. Starts your WSL2 Podman machine and enables `/dev/kvm` for rootless containers.
3. Launches the `qemux/qemu` container in the background on `127.0.0.1:8006`.

### 2. Open Yantrik OS in your browser

Navigate to `http://127.0.0.1:8006`. GRUB selects **Try Yantrik OS (live, no install)** automatically and boots straight into the graphical desktop.

### 3. Common lifecycle commands

```powershell
# Check container status
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 ps

# View QEMU / boot logs
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 logs -f

# Stop the container (keeps the named volume 'yantrik-data')
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 down
```

## 🧩 Architecture

<p align="center">
  <img src="assets/architecture.svg" alt="Yantrik OS Podman Architecture" width="100%" />
</p>

| Layer | Component | Responsibility |
| --- | --- | --- |
| Windows 11 Host | `yantrik-podman.ps1`, `scripts/download-iso.ps1`, Browser | Fetches/verifies `yantrik.iso`, manages the Podman VM, and connects to noVNC at `http://127.0.0.1:8006` |
| WSL2 Podman Machine | Fedora WSL2 VM + `/dev/kvm` + `podman-compose` | Exposes nested hardware virtualization (`/dev/kvm`) and mounts `/mnt/c/.../yantrik.iso` |
| Container Runtime | `docker.io/qemux/qemu` (QEMU 10.2 + OVMF) | Boots the hybrid GPT/ESP ISO image with `BOOT_MODE=uefi`, `8G` RAM, `4` CPU cores, and `virtio-vga` |
| Guest OS | Yantrik OS `v0.1.0-641-g9f675b7` (Debian 13 / Linux `6.12.107`) | Runs the custom display shell, 33 native apps, AI Harnesses, and the `yos` Surface Protocol daemon (`127.0.0.1:19100`) |

## 🔧 Key Fixes for Podman + `qemux/qemu`

Running Yantrik OS inside `qemux/qemu` v7.50 on Windows 11 + Podman WSL2 requires three specific adjustments over generic Docker/QEMU examples:

### 1. Use `BOOT_MODE: "uefi"` instead of `"legacy"`

`qemux/qemu` v7.50 inspects the first 512 bytes of `/boot.iso`. Because the Yantrik OS ISO is a hybrid image containing the `55aa` boot signature at offset `0x1fe`, `qemux/qemu` classifies it as a disk image rather than an optical CD-ROM and attaches it via `-device usb-storage` on a USB 3.0 (`qemu-xhci`) bus.

Meanwhile, the Yantrik OS partition table uses a GPT protective MBR (`0xee`) paired with an EFI System Partition (`/efi.img`). SeaBIOS (`BOOT_MODE: "legacy"`) cannot boot this layout from a USB storage device and fails with `No bootable device.`. Switching `compose.yaml` to `BOOT_MODE: "uefi"` boots GRUB 2.12 via OVMF without issue.

### 2. Mount `./yantrik.iso:/boot.iso` without `:ro`

Because `qemux/qemu` attaches `/boot.iso` as a read-write USB disk (`media=disk` without `readonly=on`), mounting the volume with `:ro` (`./yantrik.iso:/boot.iso:ro`) causes QEMU to abort during initialization with:

```text
qemu-system-x86_64: -device usb-storage,drive=drive0,...: Could not open '/boot.iso': Read-only file system
```

Omitting `:ro` allows QEMU to open the image descriptor while booting the live squashfs image (`Try Yantrik OS (live, no install)`).

### 3. Load `kvm_intel` / `kvm_amd` and relax `/dev/kvm` permissions inside Podman Machine

On Windows 11 + WSL2, nested virtualization is supported by the WSL2 kernel, but the Fedora-based Podman machine does not autoload the KVM kernel module or grant rootless container access to `/dev/kvm` out of the box. `yantrik-podman.ps1` automatically runs and persists:

```bash
sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null || true
sudo chmod 666 /dev/kvm
```

## 🖥️ Controlling Apps via the `yos` Surface Protocol CLI

Yantrik OS includes a built-in IPC interface called the **Surface Protocol** (`http://127.0.0.1:19100`), exposed through the `yos` CLI. Every running desktop application registers semantic state, elements, and callable actions that both human users and AI agents can inspect and invoke from the terminal:

```bash
# List running GUI apps that expose the Surface Protocol
yos ls

# Inspect semantic state, UI elements, and available actions of the Notes app
yos describe notes

# Create and save a note programmatically from the terminal
yos act notes new_note
yos act notes set_title --title "Hello from Podman + QEMU!"
yos act notes set_body --body "Yantrik OS v0.1.0 running on Windows 11 + WSL2 + Podman KVM. Automated via yos Surface Protocol CLI!"
yos act notes save_note
```

<p align="center">
  <img src="screenshots/29-yos-act-new-note.png" alt="yos act notes commands in Terminal" width="49%" />
  <img src="screenshots/30-notes-app-created-via-yos.png" alt="Note created inside the Notes GUI app" width="49%" />
</p>

## 📸 Visual Walkthrough (35 Screenshots)

All 35 step-by-step screenshots captured during the live verification session are stored in [`screenshots/`](screenshots/).

### 1. Five-Step Onboarding Wizard (`01`–`10`)

| Step 1: Identity (`02`) | Step 2: Topics (`04`) | Step 3: Location (`06`) |
| --- | --- | --- |
| ![Identity](screenshots/02-onboarding-filled.png) | ![Topics](screenshots/04-onboarding-topics-selected.png) | ![Location](screenshots/06-onboarding-location-filled.png) |

| Step 4: Hardware Scan (`07`) | Step 5: AI Mode (`08`) | Cloud Provider Setup (`10`) |
| --- | --- | --- |
| ![Hardware Scan](screenshots/07-onboarding-step4.png) | ![AI Mode](screenshots/08-onboarding-step5.png) | ![Cloud Provider](screenshots/10-onboarding-provider-google.png) |

- Additional onboarding captures: [`01-onboarding-initial.png`](screenshots/01-onboarding-initial.png), [`03-onboarding-step2.png`](screenshots/03-onboarding-step2.png), [`05-onboarding-step3.png`](screenshots/05-onboarding-step3.png), [`09-onboarding-cloud-powered.png`](screenshots/09-onboarding-cloud-powered.png)

### 2. Desktop Workspace, Command Search & App Launcher (`11`–`14`, `25`)

| Desktop Workspace (`11`) | Command Search `Super+K` (`12`) | 33 Native Apps Menu (`13`) |
| --- | --- | --- |
| ![Desktop](screenshots/11-after-skip.png) | ![Command Search](screenshots/12-command-search.png) | ![Apps Menu](screenshots/13-apps-menu.png) |

- Companion panel & prompts: [`14-companion-chat.png`](screenshots/14-companion-chat.png), [`14-connect-a-mind.png`](screenshots/14-connect-a-mind.png), [`25-companion-chat-panel.png`](screenshots/25-companion-chat-panel.png)

### 3. Settings: Harnesses, AI & Intelligence, 50 Skills & System Info (`15`–`18`)

| Harnesses / Connect a Mind (`15`) | AI & Intelligence (`16`) |
| --- | --- |
| ![Harnesses](screenshots/15-connect-a-mind-settings.png) | ![AI & Intelligence](screenshots/16-settings-ai-intelligence.png) |

| Skill Store — 50 Built-in Skills (`17`) | System Details (`18`) |
| --- | --- |
| ![Skills](screenshots/17-settings-skills.png) | ![System](screenshots/18-settings-system.png) |

### 4. Native Applications & `yos` Surface Protocol (`19`–`33`)

| Terminal (`19`) | Files (`20`) | Notes (`21`) |
| --- | --- | --- |
| ![Terminal](screenshots/19-terminal-app.png) | ![Files](screenshots/20-files-app.png) | ![Notes](screenshots/21-notes-app.png) |

| Agents (`22`) | Memories (`23`) | System Monitor (`31`) |
| --- | --- | --- |
| ![Agents](screenshots/22-agents-app.png) | ![Memories](screenshots/23-memory-app.png) | ![System Monitor](screenshots/31-system-monitor-app.png) |

| `yos ls` (`26`) | `yos describe notes` (`27`) | Arcade 2048 (`33`) |
| --- | --- | --- |
| ![yos ls](screenshots/26-terminal-yos-ls.png) | ![yos describe notes](screenshots/27-terminal-yos-describe-notes.png) | ![Arcade](screenshots/33-arcade-new-game.png) |

- Additional CLI & app captures: [`24-terminal-yos-cli.png`](screenshots/24-terminal-yos-cli.png), [`25-terminal-yos-help-top.png`](screenshots/25-terminal-yos-help-top.png), [`28-terminal-yos-notes-actions.png`](screenshots/28-terminal-yos-notes-actions.png), [`29-yos-act-new-note.png`](screenshots/29-yos-act-new-note.png), [`30-notes-app-created-via-yos.png`](screenshots/30-notes-app-created-via-yos.png), [`32-arcade-app.png`](screenshots/32-arcade-app.png)

## 📁 Repository Layout

```text
yantrik-os-podman/
├── .github/workflows/
│   └── ci.yml                 # Validates compose.yaml, PowerShell syntax, and tracked payload
├── assets/
│   ├── architecture.svg       # Windows 11 + WSL2 Podman + qemux/qemu architecture diagram
│   └── logo.svg               # Project icon
├── screenshots/               # 35 sequential screenshots of Yantrik OS onboarding, apps, and yos CLI
├── scripts/
│   └── download-iso.ps1       # Downloads and SHA256-verifies the latest Yantrik OS nightly ISO
├── compose.yaml               # Podman / Docker Compose definition (UEFI, KVM, 8G RAM, 4 cores)
├── yantrik-podman.ps1         # Windows PowerShell launcher for WSL2 Podman Machine + KVM
├── LICENSE                    # MIT License
├── README.md                  # English documentation
└── README.ja.md               # Japanese documentation
```

## 📄 License

Released under the [MIT License](LICENSE). Yantrik OS itself is developed and distributed by the [Yantrik OS project](https://yantrikos.com/).
