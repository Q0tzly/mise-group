# mise-group

English | [日本語](README.ja.md)

A small CLI to enable and disable [mise](https://mise.jdx.dev) tools by group.

> Unofficial companion CLI for mise. Not affiliated with the mise project.

mise itself has no place for "tools I want to keep on file but not install right now". Write a tool in `mise.toml` or `conf.d/` and `mise install` installs it; delete it and you forget it was ever a candidate. mise-group covers the gap in between:

- Group definitions (TOML files with a `[tools]` section) live in a groups directory as a **catalog**
- A group is enabled solely by the presence of a symlink at `~/.config/mise/conf.d/<name>.toml`
- There is no state file. The links are canonical, so creating or removing them by hand never breaks anything

It started as a script in the author's dotfiles and was extracted into its own repository.

## Setup

The recommended way is to let mise itself install it (mise then handles versioning and upgrades):

```sh
mise use -g "github:Q0tzly/mise-group@latest"
```

Alternatively, `install.sh` installs the release binary into `~/.local/bin` without going through mise:

```sh
git clone https://github.com/Q0tzly/mise-group.git
cd mise-group
./install.sh
```

- It creates the groups directory `~/.config/mise/groups/` if needed
- Implemented in Go (standard library only, static binary). v0.1 was a bash version

## Usage

A group is a TOML file with a `[tools]` section. See `examples/groups/` for an example.

```toml
# ~/.config/mise/groups/media.toml
[tools]
ffmpeg = "latest"
```

```sh
mise-group list                  # list groups ([x] = enabled)
mise-group enable media          # enable and run mise install
mise-group enable --no-install media  # just create the link
mise-group disable media         # disable and remove tools unique to that group
mise-group names                 # group names only (for scripts)
```

- `disable` never removes tools that also appear in other still-enabled configs
- The directories can be changed with environment variables:
  - `MISE_GROUPS_DIR`: where group definitions live. Default is `~/.config/mise/groups`. If a `<repo>/mise/groups` directory exists two levels above the executable (the legacy layout from when it shipped inside dotfiles), that takes precedence
  - `MISE_CONF_D`: where the links go. Default is `~/.config/mise/conf.d`

## Using it with dotfiles

Group definitions can live in your dotfiles while the tool itself comes from this repository.

The author's dotfiles are a working reference:

- [Q0tzly/dotfiles](https://github.com/Q0tzly/dotfiles) — the group definitions live in [`mise/groups/`](https://github.com/Q0tzly/dotfiles/tree/main/mise/groups) (11 groups)
- Those definitions are linked to `~/.config/mise/groups`
- The dotfiles' base tools include `"github:Q0tzly/mise-group"`, so mise distributes the binary itself (on first-time setup only, install.sh borrows it ahead of time via `mise exec`)

## Tests

```sh
tests/run.sh   # builds the binary and verifies behavior against a stub mise; never touches a real one
go vet ./...
```

Releases: pushing a tag (`v*`) makes GitHub Actions cross-build four targets
(darwin/linux × arm64/amd64) from a single runner and upload them to
GitHub Releases.

## License

Apache License 2.0 (see `LICENSE`)
