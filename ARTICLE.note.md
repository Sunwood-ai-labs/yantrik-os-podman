# AIエージェントがGUIアプリを直接操作する「Yantrik OS」を、Windows 11＋Podmanのコンテナ内で動かしてみた

AIエージェントが最初からOSの仕組みに組み込まれたLinuxディストリビューション「Yantrik OS」をご存じでしょうか。

https://yantrikos.com/

Yantrik OSはDebian 13（Linuxカーネル 6.12.107）をベースに開発されており、33種類のネイティブアプリや50種類のスキルストアに加えて、ターミナルやAIエージェントからGUIアプリの状態取得・操作を行える「Surface Protocol（`yos` CLI）」を標準搭載しています。

ただ、新しいOSを試すために実機のUSBメモリへ書き込んだり、VirtualBoxで仮想マシンを毎回手作業で構築したりするのは手間がかかります。そこで今回は、Windows 11＋WSL2上の **Podman** でQEMUコンテナ（`qemux/qemu`）を動かし、ブラウザーからYantrik OSを操作できる環境を構築しました。

![Podman＋QEMUコンテナ上で起動したYantrik OSのデスクトップ画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/11-after-skip.png)

*ブラウザーの `http://127.0.0.1:8006`（noVNC）越しに表示したYantrik OSのデスクトップ画面。*

実際に動かしてみると、一般的な `qemux/qemu` のサンプル設定のままでは起動途中で3箇所つまずくポイントがありました。本記事では、その原因と解決策、オンボーディングから標準アプリ群の探索、そして `yos` コマンドでターミナルからメモ帳アプリ（Notes）を自動操作した検証結果までをまとめます。

作成したPodman構成一式と35枚の検証スクリーンショットは、以下のGitHubリポジトリで公開しています。

https://github.com/Sunwood-ai-labs/yantrik-os-podman

---

## なぜ「Podman＋QEMUコンテナ」で動かすのか

PodmanやDockerはホストOSのカーネルを共有するコンテナランタイムであるため、単体でISOファイルを受け取って別カーネルのOSをブートすることはできません。コンテナ環境でISOイメージからOSを起動するには、コンテナの内部でQEMUなどの仮想マシンを実行し、その画面をVNCやWebサーバー経由でブラウザーへ配信する構成をとります。

その代表的なコンテナイメージが **`qemux/qemu`** です。ComposeファイルにISOイメージとKVMデバイス（`/dev/kvm`）を渡して起動すると、コンテナ内でQEMUが立ち上がり、`http://127.0.0.1:8006` をブラウザーで開くだけでデスクトップ画面を操作できます。

![Windows 11＋WSL2 Podman＋qemux/qemuの構成図](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/refs/heads/main/assets/architecture.png)

手元のWindows 11環境では、すでにOpenMausBotなどの検証用にWSL2ベースのPodman Machine（`openmausbot`）を運用していました。新たにVirtualBoxを導入する代わりに既存のPodman Machineへ相乗りすれば、コンテナの起動・停止もイメージ管理も `podman compose` に統一できます。

---

## そのままでは起動しない？ ぶつかった3つの壁と解決策

ところが、一般的な `qemux/qemu` のCompose設定例をそのまま書いて起動すると、QEMUプロセスが異常終了したり、BIOS画面で止まったりしてOSが立ち上がりませんでした。ログとISOイメージのヘッダーを調べた結果、以下の3点が原因だと分かりました。

### 1. Podman Machine内で `/dev/kvm` のモジュール読み込みと権限設定が必要

Windows 11＋WSL2自体は入れ子の仮想化（Nested Virtualization）に対応していますが、FedoraベースのPodman Machineは初期状態ではKVMカーネルモジュール（`kvm_intel` または `kvm_amd`）を自動で読み込みません。さらに、Podmanをルートレスモードで動かしている場合、一般ユーザーが `/dev/kvm` にアクセスする権限を持っていないため、QEMUがハードウェア仮想化を使えず速度が大幅に低下します。

そこで、Podman Machineの起動時にモジュールを読み込み、`/dev/kvm` のパーミッションを `0666` に変更したうえで、再起動後も維持されるよう `/etc/modules-load.d/kvm.conf` と `/etc/udev/rules.d/99-kvm.rules` に設定を書き込むようにしました。

```bash
sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null || true
sudo chmod 666 /dev/kvm
```

### 2. `./yantrik.iso:/boot.iso:ro` と読み取り専用でマウントするとQEMUが落ちる

ISOファイルを改変されないよう、ボリューム指定を `./yantrik.iso:/boot.iso:ro` と書くと、コンテナ内のQEMUが初期化段階で次のエラーを出して終了しました。

```text
qemu-system-x86_64: -device usb-storage,drive=drive0,...: Could not open '/boot.iso': Read-only file system
```

その理由は、`qemux/qemu` v7.50の起動スクリプトが `/boot.iso` の先頭512バイトを検査する仕組みにあります。Yantrik OSのISOはUSBメモリにもそのまま書き込めるハイブリッドISOであり、オフセット `0x1fe` にブート署名 `55aa` を持っています。`qemux/qemu` はこの署名を見つけると、光学CD-ROMではなくUSBディスク（`-device usb-storage`、`readonly=on` なし）としてQEMUに接続します。そのため、コンテナのボリュームを `:ro` にしているとQEMUが読み書きモードでファイルを開けずエラーになります。

ボリューム指定から `:ro` を外し、`./yantrik.iso:/boot.iso` とすることでこの問題を解消しました。

### 3. `BOOT_MODE: "legacy"` では `No bootable device.` になる

`:ro` を外してQEMUが起動するようになっても、`BOOT_MODE: "legacy"`（SeaBIOS）のままでは `No bootable device.` と表示されてブートが止まりました。

Yantrik OSのISOイメージのパーティションテーブルを確認すると、GPT保護MBR（タイプ `0xee`）とEFIシステムパーティション（`/efi.img`）で構成されていました。前項のとおり `qemux/qemu` はこのISOをUSB 3.0（`qemu-xhci`）上のディスクとして接続するため、レガシーBIOSのSeaBIOSからはブートローダーを見つけられません。

`compose.yaml` の環境変数を `BOOT_MODE: "uefi"` に変更してOVMF（UEFIファームウェア）を有効にしたところ、GRUB 2.12メニューから `Try Yantrik OS (live, no install)` が自動選択され、ライブ環境のデスクトップが無事に立ち上がりました。

```yaml
services:
  yantrik:
    image: docker.io/qemux/qemu
    environment:
      BOOT_MODE: "uefi"
      RAM_SIZE: "8G"
      CPU_CORES: "4"
      DISK_SIZE: "32G"
      VGA: "virtio"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - "127.0.0.1:8006:8006"
    volumes:
      - ./yantrik.iso:/boot.iso
      - yantrik-data:/storage
    stop_grace_period: 2m

volumes:
  yantrik-data:
```

---

## Yantrik OSを実際に触ってみる（オンボーディング〜標準アプリ探索）

ブートが完了すると、最初に5ステップのオンボーディングウィザードが表示されます。

### 1. 5ステップの初期オンボーディング

Step 1ではユーザー名と利用目的（Building software / Research & learning など）を入力します。

![Step 1: 名前と利用目的の入力画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/02-onboarding-filled.png)

Step 2では関心のあるトピック（AI & ML、Systems、Open Sourceなど）、Step 3では現在地（`Tokyo`）とタイムゾーンを設定します。

![Step 2: 関心トピックの選択画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/04-onboarding-topics-selected.png)

![Step 3: 地域設定画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/06-onboarding-location-filled.png)

続くStep 4ではシステムハードウェアの自動診断が行われ、QEMUコンテナに割り当てた4コアCPUと8GB RAMが認識されました。

![Step 4: ハードウェア診断画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/07-onboarding-step4.png)

最後のStep 5では、AIの実行モードを「Local First（ローカル推論）」「Cloud Powered（クラウドAPI）」「Configure Later（後で設定）」の3つから選びます。Cloud Poweredを選ぶと、OpenAI、Anthropic、Google、DeepSeek、OpenRouterの各APIキーをその場で登録できます。

![Step 5: AI実行モードの選択画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/08-onboarding-step5.png)

![Cloud Powered選択時のプロバイダー設定画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/10-onboarding-provider-google.png)

### 2. デスクトップ画面と33種類のネイティブアプリ

オンボーディングを完了（またはスキップ）すると、ダークテーマを基調とした独自デスクトップシェルが表示されます。画面上部の検索バー（`Super + K`）からはコマンド検索やアプリの呼び出しができ、左上の「Apps」メニューを開くと33種類のネイティブアプリがカテゴリ別に並んでいます。

![Super+Kによるコマンド検索画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/12-command-search.png)

![33種類のネイティブアプリが並ぶAppsメニュー](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/13-apps-menu.png)

画面右側のサイドパネルにはAIコンパニオン（Companion Chat）が常駐しており、作業中の画面のすぐ隣でチャットやタスク指示を行えるレイアウトになっています。

![右側に表示されるCompanion Chatパネル](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/25-companion-chat-panel.png)

### 3. 設定画面：4種類のAIハーネスと50種類のスキルストア

設定アプリ（Settings）を開くと、Yantrik OSがどのようにAIエージェントをOSへ統合しているかがよく分かります。

「Harnesses」タブでは、OS標準の **Yantrik Companion** だけでなく、**DeepSeek**、**Hermes**（Nous Research）、**OpenClaw** といった複数のエージェントハーネスを切り替えたり追加したりできます。

![Settings内のHarnesses（Connect a Mind）画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/15-connect-a-mind-settings.png)

「AI & Intelligence」タブでは、ローカルLLMサーバー（`llama-server`）の稼働状態確認や、コンテキストウィンドウ上限（8,192トークン）・自律実行ループの最大ステップ数（15ステップ）などを細かく調整できます。

![Settings内のAI & Intelligence設定画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/16-settings-ai-intelligence.png)

さらに「Skills」タブには、コードレビュー、Gitワークフロー、システム診断、ドキュメント生成など **50種類の組み込みスキル** があらかじめ用意されており、各スキルの有効・無効をスイッチ一つで切り替えられます。

![50種類のスキルが並ぶSkill Store画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/17-settings-skills.png)

「System」タブを確認すると、OSバージョンは `v0.1.0-641-g9f675b7`、ベースはDebian GNU/Linux 13（trixie）、カーネルは `6.12.107` で動作していました。

![Settings内のSystem情報画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/18-settings-system.png)

### 4. 標準アプリの動作確認

標準搭載されているアプリ群も一通り起動してみました。ファイル管理（Files）、メモ帳（Notes）、エージェント管理（Agents）、長期記憶管理（Memories）、システムモニター（System Monitor）、そして息抜き用の2048ゲーム（Arcade）まで、すべて軽快に動作します。

![Filesアプリ](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/20-files-app.png)

![Agentsアプリ](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/22-agents-app.png)

![Memoriesアプリ](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/23-memory-app.png)

![System Monitorアプリ](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/31-system-monitor-app.png)

![Arcadeアプリ（2048ゲーム）](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/33-arcade-new-game.png)

---

## 本命機能：`yos` Surface Protocol CLIでターミナルからGUIアプリを自動操作する

Yantrik OSを触っていて最も驚いたのが、OS標準のプロセス間通信機構である **Surface Protocol**（`http://127.0.0.1:19100`）と、それを操作する **`yos` コマンド** です。

従来のデスクトップOSでAIエージェントにGUIアプリを操作させようとすると、画面のスクリーンショットを撮って画像認識でボタンの座標を推定し、マウスクリックをエミュレートする必要がありました。それに対してYantrik OSでは、各ネイティブアプリが自身のセマンティックな状態、UI要素、呼び出し可能なアクションをSurface Protocol経由で公開しています。

実際にターミナル（Terminalアプリ）を開き、`yos` コマンドを試してみました。

![yos --helpの実行画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/25-terminal-yos-help-top.png)

まず `yos ls` を実行すると、現在Surface Protocolを公開して稼働しているGUIアプリの一覧とプロセスIDが返ってきます。

```bash
yos ls
```

![yos lsで起動中のGUIアプリ一覧を取得した画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/26-terminal-yos-ls.png)

次に、起動しておいたメモ帳アプリ（`notes`）に対して `yos describe notes` を実行すると、現在の画面状態（選択中のノートや文字数）、UI要素、そして外部から呼び出し可能なアクション一覧（`new_note`、`set_title`、`set_body`、`save_note`、`delete_note`、`search`）がJSON形式で出力されました。

```bash
yos describe notes
```

![yos describe notesでNotesアプリの状態とアクション定義を取得した画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/27-terminal-yos-describe-notes.png)

![Notesアプリが公開しているアクション一覧（new_note, set_title, set_body, save_noteなど）](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/28-terminal-yos-notes-actions.png)

アクションの名前と引数が分かったので、そのままターミナルから `yos act` コマンドを4行叩いて、Notesアプリの中に新しいノートを作成・保存してみます。

```bash
yos act notes new_note
yos act notes set_title --title "Hello from Podman + QEMU!"
yos act notes set_body --body "Yantrik OS v0.1.0 running on Windows 11 + WSL2 + Podman KVM. Automated via yos Surface Protocol CLI!"
yos act notes save_note
```

![yos actコマンドでノート作成・タイトル設定・本文入力・保存を実行した画面](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/29-yos-act-new-note.png)

各コマンドに対して `{"ok": true}` が返ってきた直後、デスクトップ上のNotesアプリのウィンドウを確認すると、座標クリックを一切使わずにタイトルと本文が入ったノートが生成・保存されていました。

![yosコマンドによってNotesアプリのGUI上に自動作成されたノート](https://raw.githubusercontent.com/Sunwood-ai-labs/yantrik-os-podman/main/screenshots/30-notes-app-created-via-yos.png)

GUIアプリが最初から人間用の画面描画とエージェント用の構造化API（Surface Protocol）の両方を備えているため、AIエージェントが座標推定の誤差で操作に失敗することなく、デスクトップアプリを確実かつ高速に制御できる設計になっています。

---

## 手元で動かす再現手順（Windows 11＋WSL2＋Podman）

今回作成した構成は、Nightly ISOのダウンロード・SHA256検証からPodman Machineの `/dev/kvm` 設定、コンテナ起動までを1コマンドで実行できるようPowerShellスクリプトにまとめて公開しています。

https://github.com/Sunwood-ai-labs/yantrik-os-podman

### 前提条件

- WSL2と入れ子の仮想化（Nested Virtualization）を有効化したWindows 11
- Podman Desktop または Windows用Podman CLI（`podman.exe`）
- PowerShell 5.1 または PowerShell 7以降

### 1. リポジトリのクローンとセットアップ実行

WSL2からアクセスできるドライブ（`C:\Prj` など）でPowerShellを開き、以下のコマンドを実行します。

```powershell
git clone https://github.com/Sunwood-ai-labs/yantrik-os-podman.git
Set-Location yantrik-os-podman
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 setup
```

`.\yantrik-podman.ps1 setup` を実行すると、以下の処理が自動で進みます。

1. `https://iso.yantrikos.com/nightly/latest.json` から最新のNightly ISO（約1.45 GB）を `./yantrik.iso` にダウンロードし、SHA256チェックサムを検証する。
2. WSL2のPodman Machineを起動し、`kvm_intel` / `kvm_amd` の読み込みと `/dev/kvm` の権限設定（永続化ルールを含む）を適用する。
3. `qemux/qemu` コンテナをバックグラウンドで起動し、`127.0.0.1:8006` で待ち受ける。

### 2. ブラウザーからアクセスする

ブラウザーで `http://127.0.0.1:8006` を開くと、GRUBから自動的にライブ環境がブートし、Yantrik OSのデスクトップが表示されます。

### 3. 状態確認と停止

コンテナの状態確認やログ表示、停止は以下のコマンドで行えます。

```powershell
# 稼働状態の確認
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 ps

# ブートログ・QEMUログの確認
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 logs -f

# コンテナの停止（名前付きボリューム yantrik-data は保持）
powershell -ExecutionPolicy Bypass -File .\yantrik-podman.ps1 down
```

---

## スクリーンショット＋座標クリックに頼らないエージェントOSの体験

Windows 11＋WSL2上のPodmanと `qemux/qemu` を組み合わせることで、実機環境を汚さずにブラウザーからYantrik OSを一通り体験できました。なかでも、`yos`（Surface Protocol CLI）によって「ターミナルから構造化コマンドでGUIアプリを直接制御する」仕組みは、従来のスクリーンショット＋座標クリック型のComputer Useとは異なるアプローチとして実際に触ってみる価値があります。

Windows＋Podman環境がある方は、公開リポジトリの `.\yantrik-podman.ps1 setup` から手元で動かしてみてください。

https://github.com/Sunwood-ai-labs/yantrik-os-podman
