// Command mise-group enables and disables groups of mise tools.
//
// A group is a TOML file of [tools] in the groups directory. A group is
// enabled when ~/.config/mise/conf.d/<name>.toml links to its file, so the
// enabled set needs no state file of its own: files that are only listed
// in the groups directory are a catalog of tools you may install later,
// and nothing is installed until a group is enabled.
//
// Groups directory resolution, first match wins:
//  1. $MISE_GROUPS_DIR
//  2. <exe>/../../mise/groups (legacy layout, groups kept inside a dotfiles repo)
//  3. ~/.config/mise/groups
//
// The conf.d directory can be overridden with $MISE_CONF_D.
//
// Standard library only, on purpose: the whole tool is symlink management
// plus calling mise, and a zero-dependency static binary stays trivial to
// cross-compile for every target.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// version is set at release time with -ldflags "-X main.version=vX.Y.Z".
var version = "dev"

var (
	groupsDir string
	confD     string
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	resolveDirs(home)
	// mise also reads ./mise/config.toml as a project config, so never
	// run mise from a repo directory.
	_ = os.Chdir(home)

	if len(args) == 0 {
		usage()
		return 1
	}
	switch args[0] {
	case "list":
		if !requireGroupsDir() {
			return 1
		}
		return cmdList()
	case "enable":
		if !requireGroupsDir() {
			return 1
		}
		return cmdEnable(args[1:])
	case "disable":
		if !requireGroupsDir() {
			return 1
		}
		return cmdDisable(args[1:])
	case "names":
		if !requireGroupsDir() {
			return 1
		}
		for _, g := range allGroups() {
			fmt.Println(g)
		}
		return 0
	case "version", "--version":
		fmt.Printf("mise-group %s\n", version)
		return 0
	default:
		usage()
		return 1
	}
}

func resolveDirs(home string) {
	if v := os.Getenv("MISE_GROUPS_DIR"); v != "" {
		groupsDir = v
	} else if legacy := legacyGroupsDir(); legacy != "" {
		groupsDir = legacy
	} else {
		groupsDir = filepath.Join(home, ".config", "mise", "groups")
	}
	if v := os.Getenv("MISE_CONF_D"); v != "" {
		confD = v
	} else {
		confD = filepath.Join(home, ".config", "mise", "conf.d")
	}
}

// legacyGroupsDir supports the layout where the tool lived inside a
// dotfiles repo as scripts/mise-group (later bin/mise-group), with the
// group files in <repo>/mise/groups next to it.
func legacyGroupsDir() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	root := filepath.Dir(filepath.Dir(exe)) // <root>/bin/<exe>
	candidate := filepath.Join(root, "mise", "groups")
	if st, err := os.Stat(candidate); err == nil && st.IsDir() {
		return candidate
	}
	return ""
}

func usage() {
	fmt.Printf(`usage: mise-group list
       mise-group enable [--no-install] <group>...
       mise-group disable <group>...
       mise-group names
       mise-group version

Groups are TOML files in %s
(set MISE_GROUPS_DIR to use another directory).
`, groupsDir)
}

func requireGroupsDir() bool {
	if st, err := os.Stat(groupsDir); err != nil || !st.IsDir() {
		fmt.Fprintf(os.Stderr, "no groups directory: %s\n", groupsDir)
		fmt.Fprintln(os.Stderr, "create it and put <group>.toml files there, or set MISE_GROUPS_DIR.")
		return false
	}
	return true
}

func groupFile(name string) (string, bool) {
	f := filepath.Join(groupsDir, name+".toml")
	if st, err := os.Stat(f); err != nil || st.IsDir() {
		fmt.Fprintf(os.Stderr, "unknown group: %s (see: mise-group list)\n", name)
		return "", false
	}
	return f, true
}

func isEnabled(name string) bool {
	_, err := os.Lstat(filepath.Join(confD, name+".toml"))
	return err == nil
}

// allGroups returns the group names in filename order, like a shell glob.
func allGroups() []string {
	entries, err := os.ReadDir(groupsDir)
	if err != nil {
		return nil
	}
	var names []string
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".toml") {
			continue
		}
		names = append(names, strings.TrimSuffix(e.Name(), ".toml"))
	}
	sort.Strings(names)
	return names
}

var keyRe = regexp.MustCompile(`^("[^"]+"|[A-Za-z0-9_.:@\/-]+)\s*=`)

// toolsOf returns the tool names declared under [tools], in file order.
// Values may be strings ("latest") or tables ({ version = ... }); only
// the keys matter here.
func toolsOf(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var tools []string
	inTools := false
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "[") {
			inTools = trimmed == "[tools]"
			continue
		}
		if !inTools || trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		m := keyRe.FindStringSubmatch(trimmed)
		if m == nil {
			continue
		}
		tools = append(tools, strings.Trim(m[1], `"`))
	}
	return tools
}

func cmdList() int {
	for _, g := range allGroups() {
		mark := "[ ]"
		if isEnabled(g) {
			mark = "[x]"
		}
		tools := toolsOf(filepath.Join(groupsDir, g+".toml"))
		joined := ""
		if len(tools) > 0 {
			joined = strings.Join(tools, " ") + " "
		}
		fmt.Printf("%s %-12s %s\n", mark, g, joined)
	}
	return 0
}

func cmdEnable(args []string) int {
	install := true
	if len(args) > 0 && args[0] == "--no-install" {
		install = false
		args = args[1:]
	}
	if len(args) == 0 {
		usage()
		return 1
	}
	// Validate all groups before touching anything.
	files := make(map[string]string, len(args))
	for _, g := range args {
		f, ok := groupFile(g)
		if !ok {
			return 1
		}
		files[g] = f
	}
	if err := os.MkdirAll(confD, 0o755); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	for _, g := range args {
		link := filepath.Join(confD, g+".toml")
		_ = os.Remove(link) // ln -sfn: replace whatever was there
		if err := os.Symlink(files[g], link); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Printf("enabled %s\n", g)
	}
	if install {
		cmd := exec.Command("mise", "install", "--yes")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Stdin = os.Stdin
		if err := cmd.Run(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	}
	return 0
}

func cmdDisable(args []string) int {
	if len(args) == 0 {
		usage()
		return 1
	}
	for _, g := range args {
		file, ok := groupFile(g)
		if !ok {
			return 1
		}
		_ = os.Remove(filepath.Join(confD, g+".toml"))
		fmt.Printf("disabled %s\n", g)
		// Only remove tools that no remaining config still lists.
		for _, tool := range toolsOf(file) {
			out, _ := exec.Command("mise", "ls", "--json", tool).Output()
			if strings.Contains(string(out), `"source"`) {
				fmt.Printf("  keep %s (used by another config)\n", tool)
				continue
			}
			cmd := exec.Command("mise", "uninstall", "--all", tool)
			if err := cmd.Run(); err == nil {
				fmt.Printf("  removed %s\n", tool)
			}
		}
	}
	return 0
}
