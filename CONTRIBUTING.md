# Contributing

Issues and pull requests are welcome. This is a small project maintained on a best-effort basis, so replies may take a while.

## Before you start

- For anything larger than a small fix, please open an issue first so we can agree on the direction.
- Keep changes small and focused. The CLI intentionally has a tiny surface: `list`, `enable`, `disable`, and `names`.

## Development

- Go, **standard library only**. Please do not add external dependencies; the single static binary is a feature.
- Build and test:

```sh
go build ./...
go vet ./...
tests/run.sh
```

`tests/run.sh` builds the binary and checks its behavior against a stub `mise`; it never touches your real mise installation.

## Pull requests

- Make sure the commands above pass.
- If behavior changes, update the README (and `README.ja.md` if you can) and the tests.
