# mise-group

[mise](https://mise.jdx.dev) のツールを「グループ」単位で有効／無効にする小さな CLI。

> Unofficial companion CLI for mise. Not affiliated with the mise project.

mise 本体には「ファイルに残しておくけど今はインストールしないツール置き場」が無い。`mise.toml` や `conf.d/` に書けば `mise install` で入ってしまうし、消せば候補だったこと自体を忘れる。mise-group はその間を担う：

- グループ定義（`[tools]` の TOML）は**カタログ**としてグループ用ディレクトリに置いておく
- 有効化は `~/.config/mise/conf.d/<グループ名>.toml` へのシンボリックリンクの有無だけ
- 状態ファイルは持たない。リンクが正（canonical）なので、リンクを手で作ったり消したりしても壊れない

もともと作者の dotfiles の中の一スクリプトだったものを、独立リポジトリに切り出した。

## セットアップ

推奨は mise 自身で入れる方法（バージョン管理とアップグレードも mise が担う）：

```sh
mise use -g "github:Q0tzly/mise-group@latest"
```

mise を介さない場合は、リリースバイナリを `~/.local/bin` に入れる install.sh もある：

```sh
git clone https://github.com/Q0tzly/mise-group.git
cd mise-group
./install.sh
```

- グループ用ディレクトリ `~/.config/mise/groups/` を用意（無ければ作る）
- 実装は Go（標準ライブラリのみ、静的バイナリ）。v0.1 は bash 版だった

## 使い方

グループは `[tools]` を書いた TOML ファイル。`examples/groups/` に例がある。

```toml
# ~/.config/mise/groups/media.toml
[tools]
ffmpeg = "latest"
```

```sh
mise-group list                  # 一覧（[x] が有効）
mise-group enable media          # 有効化して mise install
mise-group enable --no-install media  # リンクだけ作る
mise-group disable media         # 無効化して、そのグループ固有のツールを削除
mise-group names                 # グループ名だけ（スクリプト用）
```

- `disable` は、他の有効な設定にも載っているツールは消さない
- グループ用ディレクトリの場所は環境変数で変えられる：
  - `MISE_GROUPS_DIR`: グループ定義の置き場。既定は `~/.config/mise/groups`。ただしスクリプトの隣に `<repo>/mise/groups` がある配置（dotfiles に同梱する旧レイアウト）ではそちらが優先される
  - `MISE_CONF_D`: リンク先。既定は `~/.config/mise/conf.d`

## dotfiles と組み合わせる場合

グループ定義は dotfiles 側に置き、ツールだけをこのリポジトリから入れる、という分担ができる。作者の dotfiles では：

- `mise/groups/*.toml`（定義）を `~/.config/mise/groups` にリンク
- dotfiles の base ツールに `"github:Q0tzly/mise-group"` が入っていて、mise が本体を配る（初回構築時だけ install.sh が `mise exec` で先行して借りる）

という形で使っている。

## テスト

```sh
tests/run.sh   # バイナリをビルドし、スタブの mise で挙動を検証。本物には触らない
go vet ./...
```

リリースはタグ（`v*`）を push すると GitHub Actions が4ターゲット
（darwin/linux × arm64/amd64）を1台のランナーからクロスビルドして
GitHub Releases に上げる。

## ライセンス

Apache License 2.0（`LICENSE` 参照）
