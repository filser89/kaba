package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

type listedPackage struct {
	ImportPath   string
	Dir          string
	GoFiles      []string
	CgoFiles     []string
	TestGoFiles  []string
	XTestGoFiles []string
	Imports      []string
	TestImports  []string
	XTestImports []string
	ForTest      string
	Error        *struct{ Err string }
}

func inventoryCommand(args []string) error {
	flags := flag.NewFlagSet("identities", flag.ContinueOnError)
	root := flags.String("root", "", "consumer repository root")
	goBin := flags.String("go-bin", "go", "Go executable for package discovery")
	packages := flags.String("packages", "./...", "space-separated Go package selection")
	tags := flags.String("tags", "", "Go build tags")
	overlay := flags.String("overlay", "", "validated internal overlay for matching build context")
	permissions := flags.String("permission-helper", "", "shared path classifier for ordinary test-owned Go support")
	includeSourceFiles := flags.Bool("include-source-files", false, "emit records and all selected test source paths")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *root == "" {
		return fmt.Errorf("--root is required")
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected arguments")
	}
	abs, err := filepath.Abs(*root)
	if err != nil {
		return err
	}
	command := []string{"list", "-e", "-json", "-mod=readonly"}
	if *tags != "" {
		command = append(command, "-tags", *tags)
	}
	if *overlay != "" {
		command = append(command, "-overlay", *overlay)
	}
	selected := strings.Fields(*packages)
	if len(selected) == 0 {
		return fmt.Errorf("empty package selection")
	}
	for _, p := range selected {
		if strings.HasPrefix(p, "-") {
			return fmt.Errorf("invalid package selection %q", p)
		}
	}
	command = append(command, selected...)
	listed, err := listPackages(*goBin, abs, command)
	if err != nil {
		return err
	}
	if len(listed) == 0 {
		return fmt.Errorf("package selection matched no packages")
	}
	owned := map[string][]string{}
	graph := map[string]listedPackage{}
	if *permissions != "" {
		dependencyCommand := append([]string{"list", "-deps", "-test"}, command[1:]...)
		dependencies, err := listPackages(*goBin, abs, dependencyCommand)
		if err != nil {
			return err
		}
		synthetic := map[string]bool{}
		for _, dependency := range dependencies {
			if dependency.ForTest != "" {
				synthetic[dependency.ForTest+".test"] = true
			}
		}
		for _, dependency := range dependencies {
			// Ignore synthetic test binaries and augmented test-package variants.
			if dependency.ForTest != "" || strings.Contains(dependency.ImportPath, " [") || synthetic[dependency.ImportPath] {
				continue
			}
			graph[dependency.ImportPath] = dependency
		}
		owned, err = ownedGoSources(abs, *permissions, graph)
		if err != nil {
			return err
		}
	}
	records := []Record{}
	sourceFiles := []string{}
	seen := map[string]bool{}
	for _, pkg := range listed {
		if pkg.Error != nil {
			return fmt.Errorf("package %s: %s", pkg.ImportPath, pkg.Error.Err)
		}
		rel, err := filepath.Rel(abs, pkg.Dir)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return fmt.Errorf("package %s is outside repository", pkg.ImportPath)
		}
		selectedFiles := append(pkg.TestGoFiles, pkg.XTestGoFiles...)
		for _, name := range selectedFiles {
			sourceFiles = append(sourceFiles, filepath.ToSlash(filepath.Join(rel, name)))
		}
		supportFiles := append(append([]string{}, selectedFiles...), owned[pkg.ImportPath]...)
		items, err := scanPackage(pkg.ImportPath, pkg.Dir, rel, supportFiles)
		if err != nil {
			return err
		}
		imported, err := importedSupportDigest(abs, pkg, graph, owned)
		if err != nil {
			return err
		}
		for _, item := range items {
			if imported != "" {
				item.Digest = structuralHash([]string{item.Digest, imported})
			}
			if seen[item.ID] {
				return fmt.Errorf("duplicate runtime identity %s", item.ID)
			}
			seen[item.ID] = true
			records = append(records, item)
		}
	}
	sortRecords(records)
	if *includeSourceFiles {
		sort.Strings(sourceFiles)
		return json.NewEncoder(os.Stdout).Encode(struct {
			Records     []Record `json:"records"`
			SourceFiles []string `json:"source_files"`
		}{records, sourceFiles})
	}
	return json.NewEncoder(os.Stdout).Encode(records)
}
func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: go-helper identities|digests --root REPO")
		os.Exit(1)
	}
	var err error
	switch os.Args[1] {
	case "cleanup":
		err = cleanupCommand(os.Args[2:])
	case "scaffold":
		err = scaffoldCommand(os.Args[2:])
	case "quality":
		err = qualityCommand(os.Args[2:])
	case "identities", "digests":
		err = inventoryCommand(os.Args[2:])
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "Go helper:", err)
		os.Exit(1)
	}
}

func listPackages(goBin, root string, args []string) ([]listedPackage, error) {
	cmd := exec.Command(goBin, args...)
	cmd.Dir, cmd.Stderr = root, os.Stderr
	data, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("go list: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	packages := []listedPackage{}
	for {
		var pkg listedPackage
		if err := decoder.Decode(&pkg); err == io.EOF {
			break
		} else if err != nil {
			return nil, fmt.Errorf("invalid go list output: %w", err)
		}
		packages = append(packages, pkg)
	}
	return packages, nil
}
