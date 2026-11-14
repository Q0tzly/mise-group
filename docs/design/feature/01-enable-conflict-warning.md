# 01-enable-conflict-warning

## Goal
`mise-group enable` のとき、有効化するグループが既に有効な（または同時に有効化する）他のグループと
同じツールを異なるバージョンで pin していたら、警告を出す。enable 自体は従来どおり成功させる
（意味論は変えない、警告のみ）。mise 本体はこの競合を無言で「conf.d でファイル名が辞書順で
最後のファイルの版を採用」により解決するので、ユーザーが enable の時点で気づけるようにする。

## Files
- cmd/mise-group/main.go
- tests/run.sh
- README.md
- README.ja.md

## Interface
CLI の引数・出力のうち "enabled <group>" 等の既存の行は変えない。追加するのは警告行のみで、
出力先は **stderr**、形式は次のとおり（グループは conf.d のファイル名順に並べ、勝者は最後）:

```
warning: jq is pinned by aaa (1.8.0) and zzz (1.7.1); zzz wins (last file in conf.d)
```

検出と表示の規則:
- 比較対象は [tools] のキーとバージョン指定。キーの引用符は toolsOf と同様に外して正規化する。
- バージョン指定は文字列の単純比較。値が文字列ならその文字列、テーブル形式
  （`{ version = "1.7.1", ... }`）なら version キーの値を取る。同じ指定同士は競合ではない。
- 対象は「今回有効化するグループ」×「既に有効な他のグループ」と「今回同時に有効化する
  グループ同士」の両方。有効化しないグループ同士・既存グループ同士の競合は対象外。
- 1ツールにつき勝者は1つ（関係するグループ名のうち辞書順で最後のもの）。勝者と異なる
  バージョンを pin するグループが他にあれば、そのグループと勝者のペアで警告を1行出す
  （3グループ以上が絡む場合は、異なる版のグループごとに1行でよい）。
- 警告はリンク作成の後、`mise install` 実行の前に出す。--no-install のときも出す。

## Acceptance
- `go build ./...` と `go vet ./...` が通り、`gofmt -l cmd/` が空
- `tests/run.sh` が全件 pass（既存ケースを壊さない）。追加ケース:
  - aaa（jq=1.8.0）を有効化済みの状態で zzz（jq=1.7.1）を enable → 上記形式の警告が
    stderr に出て、enable は成功する
  - 同じバージョン同士なら警告が出ない
  - 同時 enable する2グループ同士の競合でも警告が出る
  - テーブル形式 `{ version = "..." }` の指定も検出できる
  - 競合が無ければ警告が出ない
- README.md / README.ja.md の競合の段落（"different versions of the same tool" /
  「同じツールの異なるバージョン」の行）に、「enable のときに mise-group が警告を出す」
  旨の1文を足す

## Notes
- 標準ライブラリのみ（repo の方針）。既存の toolsOf の行スキャン方式に合わせ、
  バージョン値も同じ流儀で取ること（本格的な TOML パーサは入れない）。
- disable 側は変更しない。list の表示も変更しない。
- バージョン番号（version 定数やタグ）は触らない。リリースはしない。
