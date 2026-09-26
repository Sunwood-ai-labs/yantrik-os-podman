<div align="center">
  <img src="assets/logo.svg" alt="Yantrik OS Podman ロゴ" width="96" />
  <h1>Yantrik OS Podman</h1>
  <p>Windows 11 + WSL2 上の Podman と KVM 高速化 QEMU コンテナで Yantrik OS を起動し、ブラウザーの noVNC と Surface Protocol CLI から操作する実行環境。</p>
  <p>
    <a href="https://github.com/Sunwood-ai-labs/yantrik-os-podman/actions/workflows/ci.yml"><img src="https://github.com/Sunwood-ai-labs/yantrik-os-podman/actions/workflows/ci.yml/badge.svg" alt="Repository QA" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-10B981.svg" alt="MIT License" /></a>
    <a href="https://podman.io/"><img src="https://img.shields.io/badge/Podman-WSL2%20%2B%20KVM-892CA0.svg?logo=podman&logoColor=white" alt="Podman WSL2 + KVM" /></a>
    <a href="https://github.com/qemux/qemu"><img src="https://img.shields.io/badge/qemux%2Fqemu-UEFI-38BDF8.svg" alt="qemux/qemu UEFI" /></a>
  </p>
  <p>
    <a href="README.md">English</a>
    ·
    <a href="#-クイックスタート">クイックスタート</a>
    ·
    <a href="#-podman--qemuxqemu-で起動するための修正点">技術上の修正点</a>
    ·
    <a href="#-画面ウォークスルー35枚のスクリーンショット">スクリーンショット</a>
    ·
    <a href="https://github.com/Sunwood-ai-labs/yantrik-os-podman/issues">Issues</a>
  </p>
</div>

## ✨ 概要

**Yantrik OS Podman** は、Debian 13（Linux カーネル `6.12.107`）をベースとするエージェント指向デスクトップ OS [Yantrik OS](https://yantrikos.com/) を、Windows 11 + WSL2 上の [Podman](https://podman.io/) と [`qemux/qemu`](https://github.com/qemux/qemu) コンテナで動かすための構成一式です。

USB メモリへの書き込みや VirtualBox の手動設定を行う代わりに、Nightly ISO の取得、SHA256 チェックサム検証、WSL2 Podman Machine 内の `/dev/kvm` 権限設定、コンテナの起動までを PowerShell スクリプトで自動化しています。起動後はブラウザーで `http://127.0.0.1:8006` を開くだけでデスクトップ画面を操作できます。

<p align="center">
  <img src="screenshots/11-after-skip.png" alt="Podman + QEMU コンテナ上で動作する Yantrik OS デスクトップ" width="92%" />
</p>

## 🚀 主な特徴

- **Windows 11 + WSL2 向けランチャー（`yantrik-podman.ps1`）**: WSL2 上の Podman Machine の起動、`kvm_intel` / `kvm_amd` カーネルモジュールの読み込み、`/dev/kvm` の権限設定と永続化、`podman compose` の実行を 1 コマンドで処理します。
- **Nightly ISO 自動取得スクリプト（`scripts/download-iso.ps1`）**: `https://iso.yantrikos.com/nightly/latest.json` から最新ビルドのメタデータを取得し、`curl.exe` によるレジューム付きダウンロードと SHA256 検証（`v0.1.0-641-g9f675b7`）を実行します。
- **`qemux/qemu` v7.50 とハイブリッド ISO の起動問題を解消**: OVMF による UEFI ブート（`BOOT_MODE: "uefi"`）と、USB ストレージとして認識される ISO の読み書きマウント（`:ro` なし）を `compose.yaml` に反映済みです。
- **35 枚の画面ウォークスルー（`screenshots/`）**: 5 段階のオンボーディング、33 種のネイティブアプリ、AI ハーネス設定（`Yantrik Companion`、`DeepSeek`、`Hermes`、`OpenClaw`）、50 種のスキルストア、`yos` Surface Protocol CLI による GUI アプリの自動操作までを別名ファイルで記録しています。

## ⚡ クイックスタート

### 前提条件

- WSL2 と入れ子の仮想化（Nested Virtualization）を有効化した Windows 11
- [Podman Desktop](https://podman-desktop.io/) または Windows 用 Podman CLI（`podman.exe`）
- PowerShell 5.1 または PowerShell 7 以降

### 1. リポジトリの取得と初期セットアップ

```powershell
git clone https://github.com/Sunwood-ai-labs/yantrik-os-podman.git
Set-Location yantrik-os-podman
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 setup
```

`.\yantrik-podman.ps1 setup` を実行すると、次の 3 工程が順に自動で進みます。

1. 最新の Yantrik OS Nightly ISO（約 1.45 GB）を `./yantrik.iso` にダウンロードし、SHA256 ハッシュを照合する。
2. WSL2 の Podman Machine を起動し、ルートレスコンテナから `/dev/kvm` を利用できる状態に設定する。
3. `qemux/qemu` コンテナをバックグラウンドで起動し、`127.0.0.1:8006` で noVNC サーバーを公開する。

### 2. ブラウザーからデスクトップを開く

ブラウザーで `http://127.0.0.1:8006` を開きます。GRUB ブートローダーが **Try Yantrik OS (live, no install)** を自動選択し、そのままグラフィカルデスクトップが立ち上がります。

### 3. 日常の操作コマンド

```powershell
# コンテナの稼働状態を確認する
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 ps

# QEMU とブート処理のログを表示する
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 logs -f

# コンテナを停止する（名前付きボリューム 'yantrik-data' は保持）
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 down
```

## 🧩 アーキテクチャ

<p align="center">
  <img src="assets/architecture.svg" alt="Yantrik OS Podman アーキテクチャ図" width="100%" />
</p>

| レイヤー | コンポーネント | 役割 |
| --- | --- | --- |
| Windows 11 ホスト | `yantrik-podman.ps1`、`scripts/download-iso.ps1`、ブラウザー | `yantrik.iso` の取得・検証、Podman VM の起動管理、`http://127.0.0.1:8006`（noVNC）への接続 |
| WSL2 Podman Machine | Fedora WSL2 VM + `/dev/kvm` + `podman-compose` | 入れ子のハードウェア仮想化（`/dev/kvm`）の提供と `/mnt/c/.../yantrik.iso` のマウント |
| コンテナランタイム | `docker.io/qemux/qemu`（QEMU 10.2 + OVMF） | ハイブリッド GPT/ESP 構成の ISO を `BOOT_MODE=uefi`・RAM `8G`・CPU `4` コア・`virtio-vga` で起動 |
| ゲスト OS | Yantrik OS `v0.1.0-641-g9f675b7`（Debian 13 / Linux `6.12.107`） | 独自ディスプレイシェル、33 種のネイティブアプリ、AI ハーネス、`yos` Surface Protocol デーモン（`127.0.0.1:19100`）の実行 |

## 🔧 Podman + `qemux/qemu` で起動するための修正点

Windows 11 + Podman WSL2 上の `qemux/qemu` v7.50 で Yantrik OS を起動するには、一般的な Docker / QEMU のサンプル構成から以下の 3 点を変更する必要があります。

### 1. `BOOT_MODE` には `"legacy"` ではなく `"uefi"` を指定する

`qemux/qemu` v7.50 の起動スクリプトは、`/boot.iso` の先頭 512 バイトを検査します。Yantrik OS の ISO はオフセット `0x1fe` にブート署名 `55aa` を持つハイブリッドイメージであるため、`qemux/qemu` はこれを光学 CD-ROM ではなくディスクイメージと判定し、USB 3.0（`qemu-xhci`）バス上の `-device usb-storage` として接続します。

一方で、Yantrik OS のパーティションテーブルは GPT 保護 MBR（`0xee`）と EFI システムパーティション（`/efi.img`）で構成されています。SeaBIOS（`BOOT_MODE: "legacy"`）はこの USB ディスク構成から起動できず `No bootable device.` で停止するため、`compose.yaml` で `BOOT_MODE: "uefi"`（OVMF）を指定して GRUB 2.12 を起動します。

### 2. `./yantrik.iso:/boot.iso` に `:ro` を付けない

前項のとおり `qemux/qemu` は `/boot.iso` を読み書き可能な USB ディスク（`media=disk`、`readonly=on` なし）として QEMU に渡します。そのため、ボリューム指定に `:ro` を付けて `./yantrik.iso:/boot.iso:ro` とすると、QEMU の初期化時に次のエラーが発生してプロセスが終了します。

```text
qemu-system-x86_64: -device usb-storage,drive=drive0,...: Could not open '/boot.iso': Read-only file system
```

`:ro` を外してマウントすれば QEMU がファイルディスクリプタを開けるようになり、ライブ環境の squashfs イメージ（`Try Yantrik OS (live, no install)`）がそのまま起動します。

### 3. Podman Machine 内で `kvm_intel` / `kvm_amd` の読み込みと `/dev/kvm` の権限設定を行う

Windows 11 の WSL2 カーネルは入れ子の仮想化に対応していますが、Fedora ベースの Podman Machine は初期状態では KVM モジュールを自動読み込みせず、またルートレス実行ユーザーが `/dev/kvm` にアクセスする権限も持っていません。`yantrik-podman.ps1` はコンテナ起動前に以下のコマンドを実行し、`/etc/modules-load.d/kvm.conf` と `/etc/udev/rules.d/99-kvm.rules` にも設定を書き込んで永続化します。

```bash
sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null || true
sudo chmod 666 /dev/kvm
```

## 🖥️ `yos` Surface Protocol CLI による GUI アプリの操作

Yantrik OS は **Surface Protocol**（`http://127.0.0.1:19100`）と呼ばれるプロセス間通信機構を備えており、ターミナルの `yos` コマンドから利用できます。起動中の各デスクトップアプリは自身の状態、UI 要素、呼び出し可能なアクションを公開しているため、人間も AI エージェントもターミナルから GUI アプリを直接操作できます。

```bash
# Surface Protocol を公開している実行中 GUI アプリの一覧を表示する
yos ls

# Notes アプリのセマンティック状態、UI 要素、アクション定義を確認する
yos describe notes

# ターミナルから Notes アプリを操作して新規ノートを作成・保存する
yos act notes new_note
yos act notes set_title --title "Hello from Podman + QEMU!"
yos act notes set_body --body "Yantrik OS v0.1.0 running on Windows 11 + WSL2 + Podman KVM. Automated via yos Surface Protocol CLI!"
yos act notes save_note
```

<p align="center">
  <img src="screenshots/29-yos-act-new-note.png" alt="ターミナルでの yos act notes 実行画面" width="49%" />
  <img src="screenshots/30-notes-app-created-via-yos.png" alt="yos コマンドによって Notes アプリ内に作成されたノート" width="49%" />
</p>

## 📸 画面ウォークスルー（35枚のスクリーンショット）

動作確認セッションで順番に取得した全 35 枚のスクリーンショットは [`screenshots/`](screenshots/) に収録しています。

### 1. 5段階のオンボーディングウィザード（`01`〜`10`）

| Step 1: 名前と用途（`02`） | Step 2: 関心トピック（`04`） | Step 3: 地域設定（`06`） |
| --- | --- | --- |
| ![Identity](screenshots/02-onboarding-filled.png) | ![Topics](screenshots/04-onboarding-topics-selected.png) | ![Location](screenshots/06-onboarding-location-filled.png) |

| Step 4: ハードウェア診断（`07`） | Step 5: AI モード選択（`08`） | クラウドプロバイダー設定（`10`） |
| --- | --- | --- |
| ![Hardware Scan](screenshots/07-onboarding-step4.png) | ![AI Mode](screenshots/08-onboarding-step5.png) | ![Cloud Provider](screenshots/10-onboarding-provider-google.png) |

- その他のオンボーディング画面: [`01-onboarding-initial.png`](screenshots/01-onboarding-initial.png)、[`03-onboarding-step2.png`](screenshots/03-onboarding-step2.png)、[`05-onboarding-step3.png`](screenshots/05-onboarding-step3.png)、[`09-onboarding-cloud-powered.png`](screenshots/09-onboarding-cloud-powered.png)

### 2. デスクトップ、コマンド検索、アプリランチャー（`11`〜`14`、`25`）

| デスクトップ初期画面（`11`） | コマンド検索 `Super+K`（`12`） | 33種のネイティブアプリ一覧（`13`） |
| --- | --- | --- |
| ![Desktop](screenshots/11-after-skip.png) | ![Command Search](screenshots/12-command-search.png) | ![Apps Menu](screenshots/13-apps-menu.png) |

- コンパニオンパネルと接続案内: [`14-companion-chat.png`](screenshots/14-companion-chat.png)、[`14-connect-a-mind.png`](screenshots/14-connect-a-mind.png)、[`25-companion-chat-panel.png`](screenshots/25-companion-chat-panel.png)

### 3. 設定画面：Harnesses、AI & Intelligence、50種のスキル、システム情報（`15`〜`18`）

| Harnesses / Connect a Mind（`15`） | AI & Intelligence（`16`） |
| --- | --- |
| ![Harnesses](screenshots/15-connect-a-mind-settings.png) | ![AI & Intelligence](screenshots/16-settings-ai-intelligence.png) |

| Skill Store — 標準搭載の 50 スキル（`17`） | システム情報（`18`） |
| --- | --- |
| ![Skills](screenshots/17-settings-skills.png) | ![System](screenshots/18-settings-system.png) |

### 4. ネイティブアプリと `yos` Surface Protocol（`19`〜`33`）

| Terminal（`19`） | Files（`20`） | Notes（`21`） |
| --- | --- | --- |
| ![Terminal](screenshots/19-terminal-app.png) | ![Files](screenshots/20-files-app.png) | ![Notes](screenshots/21-notes-app.png) |

| Agents（`22`） | Memories（`23`） | System Monitor（`31`） |
| --- | --- | --- |
| ![Agents](screenshots/22-agents-app.png) | ![Memories](screenshots/23-memory-app.png) | ![System Monitor](screenshots/31-system-monitor-app.png) |

| `yos ls`（`26`） | `yos describe notes`（`27`） | Arcade 2048（`33`） |
| --- | --- | --- |
| ![yos ls](screenshots/26-terminal-yos-ls.png) | ![yos describe notes](screenshots/27-terminal-yos-describe-notes.png) | ![Arcade](screenshots/33-arcade-new-game.png) |

- その他の CLI・アプリ画面: [`24-terminal-yos-cli.png`](screenshots/24-terminal-yos-cli.png)、[`25-terminal-yos-help-top.png`](screenshots/25-terminal-yos-help-top.png)、[`28-terminal-yos-notes-actions.png`](screenshots/28-terminal-yos-notes-actions.png)、[`29-yos-act-new-note.png`](screenshots/29-yos-act-new-note.png)、[`30-notes-app-created-via-yos.png`](screenshots/30-notes-app-created-via-yos.png)、[`32-arcade-app.png`](screenshots/32-arcade-app.png)

## 📁 ディレクトリ構成

```text
yantrik-os-podman/
├── .github/workflows/
│   └── ci.yml                 # compose.yaml、PowerShell 構文、追跡対象ファイルの検証
├── assets/
│   ├── architecture.svg       # Windows 11 + WSL2 Podman + qemux/qemu の構成図
│   └── logo.svg               # プロジェクトアイコン
├── screenshots/               # オンボーディング、各種アプリ、yos CLI の連続スクリーンショット（35枚）
├── scripts/
│   └── download-iso.ps1       # Yantrik OS Nightly ISO のダウンロードと SHA256 検証
├── compose.yaml               # Podman / Docker Compose 定義（UEFI、KVM、8G RAM、4 コア）
├── yantrik-podman.ps1         # WSL2 Podman Machine + KVM 用 PowerShell ランチャー
├── LICENSE                    # MIT ライセンス
├── README.md                  # 英語版ドキュメント
└── README.ja.md               # 日本語版ドキュメント
```

## 📄 ライセンス

本リポジトリのスクリプトおよび構成ファイルは [MIT License](LICENSE) の下で公開しています。Yantrik OS 本体は [Yantrik OS プロジェクト](https://yantrikos.com/) によって開発・配布されています。
