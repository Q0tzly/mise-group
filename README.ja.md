# mise-group

[English](README.md) | 日本語

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
- 有効な2つのグループが**同じツールの異なるバージョン**を指定した場合、競合の解決は mise 本体の仕様に従う：`conf.d/` 内でファイル名が辞書順で最後のファイルのバージョンが勝ち（`zzz.toml` が `aaa.toml` に勝つ）、バージョンの新旧は無関係で、mise 側に警告は出ない。ただし `mise-group enable` は、有効化したグループがこの競合を作る場合に警告を出す（有効化自体は行う）。勝った側のグループを無効化すると、もう一方の pin が要求バージョンになる。その際、他の設定がまだツールを載せている限りアンインストールはされないが、そのバージョンが未インストールなら次の `mise install` まで missing 扱いになる。mise 2026.11.5 で実測確認済み
- グループ用ディレクトリの場所は環境変数で変えられる：
  - `MISE_GROUPS_DIR`: グループ定義の置き場。既定は `~/.config/mise/groups`。ただし実行ファイルの2階層上に `<repo>/mise/groups` がある配置（dotfiles に同梱していた旧レイアウト）ではそちらが優先される
  - `MISE_CONF_D`: リンク先。既定は `~/.config/mise/conf.d`

## dotfiles と組み合わせる場合

グループ定義は dotfiles 側に置き、ツールだけをこのリポジトリから入れる、という分担ができる。

実例として作者の dotfiles がそのまま参考になる：

- [Q0tzly/dotfiles](https://github.com/Q0tzly/dotfiles) — グループ定義は [`config/mise/groups/`](https://github.com/Q0tzly/dotfiles/tree/main/config/mise/groups) に置いてある（11グループ）
- その定義を `~/.config/mise/groups` にリンク
- dotfiles の base ツールに `"github:Q0tzly/mise-group"` が入っていて、mise が本体を配る（初回構築時だけ install.sh が `mise exec` で先行して借りる）

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
