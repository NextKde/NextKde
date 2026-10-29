<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/nextkde-logo-dark.svg">
    <img src="docs/images/nextkde-logo.svg" width="80" height="80" alt="NextKDE logo">
  </picture>
</p>

<h1 align="center">NextKDE</h1>

<p align="center"><strong>KDE Plasma のための Quickshell デスクトップ。</strong><br>
リキッドグラス、フローティングドック、そして自分好みに整えられるワークスペース。</p>

<p align="center">
  <a href="#はじめに">はじめに</a> ·
  <a href="#デスクトップ">見どころ</a> ·
  <a href="docs/Development.md">開発</a> ·
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center"><code>Plasma 6 / Wayland</code> &nbsp; <code>Quickshell 0.3.x</code> &nbsp; <code>Qt 6</code></p>

![トップバー、フローティングドック、デスクトップウィジェット、外観設定を備えた NextKDE のデスクトップ](docs/images/desktop.png)

<p align="center"><sub>NextKDE のデスクトップ · macOS 外観 · テーマ設定</sub></p>

NextKDE のデスクトップ体験は、充実しつつあるコンパニオンアプリにも広がっています。
カレンダー、天気、電卓、Todo はオプションアプリとして利用でき、
[KMusic](https://github.com/NextKde/KMusic) が音楽体験を加えます。
メールとファイルマネージャーは今後登場予定です。

![細いタブレットフレームに収められたカレンダー、KMusic、天気を並べた NextKDE アプリスイート](docs/images/apps-showcase.webp)

---

## デスクトップ

NextKDE の **KOS Desktop Shell** は、KDE Plasma 6 Wayland 上でバー、ドック、
ランチャー、検索、通知、設定をひとつにまとめます。KWin、NetworkManager、
PipeWire、BlueZ、systemd と連携します。

| ひと目でわかるワークスペース | 動きのあるデスクトップ | 選べる外観 |
| :--- | :--- | :--- |
| 時計、天気、カレンダー、システムメトリクス、アプリ使用状況、メディアウィジェット。 | フローティングドック、ウィンドウプレビュー、アプリ検索、フルスクリーンランチャー。 | リキッドグラス、ソフトライトとフロスト素材、またはトーンを抑えた Material Design インターフェース。 |

- **トップバーとシステムメニュー** — アプリメニュー、システム状態、設定やセッション操作をまとめた NextKDE ロゴメニュー。
- **コントロールセンター** — Wi-Fi、Bluetooth、音量、明るさ、スクリーンショット、おやすみモード。
- **デスクトップファイル** — 開く、名前変更、コピー、移動、削除、アプリケーションの選択。
- **設定とモーション** — バー、ドック、ランチャー、ショートカット、ウィンドウ装飾、アニメーションを設定。

カレンダー、電卓、Todo、天気は
[オプションの単体アプリケーション](apps/README.md)として利用できます。
`./tools/kosctl install apps` でこの 4 つがインストールされます。
ListenFree とそのオーディオ SDK は明示的に
`./tools/kosctl install apps --with-listenfree` を指定する必要があります。
詳しくは[アプリケーションのインストールガイド](docs/GettingStarted.md#optional-standalone-applications)を参照してください。

## はじめに

**KDE Plasma 6 Wayland** セッションと **KWin 6.6+**、**Quickshell 0.3.x**、
**Qt 6.6+** を使用してください。インストールではプラットフォームサービス、
設定、KWin エフェクト、ウィンドウ装飾をビルドします。

### 1. 依存関係を準備する

ソースを選択する場合、**Git** と **Python 3.9+** も必要です。
インストールコマンドを実行する前に、お使いのディストリビューションのガイドに従ってください。

| ディストリビューション | インストールガイド |
| :--- | :--- |
| Arch Linux | [依存関係とセットアップ](docs/GettingStarted.md#1-install-requirements) |
| Debian 13 | [インストーラーと手動セットアップ](docs/GettingStarted.md#debian-13-trixie) |
| Ubuntu 26.04 | [パッケージとセットアップ](docs/GettingStarted.md#ubuntu-2604-resolute) |
| Fedora 44 | [パッケージとセットアップ](docs/GettingStarted.md#fedora-44-community-contributed) |
| openSUSE Tumbleweed | [zypper パッケージとセットアップ](docs/GettingStarted.md#opensuse-tumbleweed-community-contributed) |
| NixOS | [Flake クイックスタート](docs/nixos-quickstart.md) |

### 2. リリースを選んでインストールする

NixOS では上記の Flake ガイドに従ってください。その他のディストリビューションでは、
依存関係の準備ができたら次を実行します。

```sh
git clone --depth 1 https://github.com/SuceV587/NextKde.git
cd NextKde
./tools/kosctl update &&
./tools/kosctl doctor &&
./tools/kosctl install &&
./tools/kosctl start
```

`update` はソースを選択し、`doctor` は依存関係を確認し、`install` はデスクトップを
配置し、`start` はサービスを起動または再起動します。ソースの選択だけでは
インストールも再起動も行われません。

### バージョンの選択

既定では、`update` は[最新の正式リリース](https://github.com/SuceV587/NextKde/releases/latest)
を選択し、存在しない場合は停止します。保守されるのは最新の正式リリースのみです。
詳しくは[リリースポリシー](docs/Releasing.md)を参照してください。

開発ブランチを試すには `./tools/kosctl update main` を使用します
（Debian インストーラーでは `--version main`）。`./tools/kosctl version` は
インストール済みファイルとソースのバージョンを別々に表示します。

デスクトップの置き換え、オプションのロック画面設定、初回ログイン時の注意、
更新、アンインストールについては[インストールガイド](docs/GettingStarted.md)を参照してください。

<details>
<summary><strong>日常的に使うコマンド</strong></summary>

更新して適用する:

```sh
./tools/kosctl update &&
./tools/kosctl install &&
./tools/kosctl start
```

サービスを確認する:

```sh
systemctl --user status kos-platform.service kos-data.service kos-shell.service
```

アンインストールする:

```sh
./tools/kosctl uninstall
```

更新された KWin エフェクトのバイナリは、次回のログアウト/ログインまたは再起動後に読み込まれます。
詳しくは[日常利用ガイド](docs/GettingStarted.md#daily-use)を参照してください。

</details>

正式なガイドと AI コントリビューター向けリファレンスは
[ドキュメント索引](docs/README.md)にまとまっています。

## 内部の仕組み

```text
Quickshell Shell ──► kos-platform ──────► KWin / network / audio / Bluetooth
                 └─► kos-data-service ─► metrics / desktop data / weather
```

| プロジェクトを知る | ガイド |
| :--- | :--- |
| 各要素の関係 | [プロジェクトアーキテクチャ](docs/ProjectArchitecture.md) |
| グラス、色、外観 | [外観アーキテクチャ](docs/AppearanceArchitecture.md) |
| ドックの動作と設定 | [ドックアーキテクチャ](docs/DockArchitecture.md) |
| デスクトップアイコンの配置 | [デスクトップアイコン](docs/DesktopIcons.md) |
| 空間的な壁紙 | [デプスエンジン](docs/DepthEngine.md) |
| ソースセッション、ビルド、デバッグ | [開発ガイド](docs/Development.md) |
| 変更とプルリクエスト | [コントリビューション](CONTRIBUTING.md) |

今後の予定には、画面ごとのレイアウト、各ディスプレイで一貫したウィジェット、
設定とアプリケーションの拡充、キーボードナビゲーションとアクセシビリティの向上が含まれます。

---

## コントリビューター

NextKDE に貢献してくださるすべての方に感謝します！

<a href="https://github.com/NextKde/NextKde/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=NextKde/NextKde&amp;max=1000" alt="NextKDE コントリビューターのアバター" />
</a>

GitHub のコントリビューションから [contrib.rocks](https://contrib.rocks) で自動生成されています。

## ライセンス

プロジェクトのライセンスは [LICENSE](LICENSE) を参照してください。
同梱の Glass エフェクトには独自の[ライセンス](kwin/glass-effect/LICENSE)があります。
