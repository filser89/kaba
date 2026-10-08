package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/constant"
	"go/parser"
	"go/printer"
	"go/token"
	gotypes "go/types"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type scaffoldFile struct {
	Path    string `json:"path"`
	SHA256  string `json:"sha256"`
	Package string `json:"package"`
}
type scaffoldResult struct {
	Overlay  *string        `json:"overlay"`
	Files    []scaffoldFile `json:"files"`
	Packages []string       `json:"packages"`
}
type scaffoldSource struct {
	path string
	data []byte
	file *ast.File
}
type scaffoldType struct {
	spec   *ast.TypeSpec
	source scaffoldSource
}
type scaffoldEdit struct {
	offset int
	text   string
}

func scaffoldCommand(args []string) error {
	flags := flag.NewFlagSet("scaffold", flag.ContinueOnError)
	root := flags.String("root", "", "consumer root")
	feature := flags.String("feature", "", "feature directory")
	output := flags.String("output", "", "empty runner temporary directory")
	goBin := flags.String("go-bin", "go", "Go executable")
	packages := flags.String("packages", "./...", "package selection")
	tags := flags.String("tags", "", "build tags")
	permissions := flags.String("permission-helper", "../path-permissions.sh", "shared path classifier")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *root == "" || *feature == "" || *output == "" || flags.NArg() != 0 {
		return fmt.Errorf("scaffold requires --root, --feature and --output")
	}
	abs, err := filepath.Abs(*root)
	if err != nil {
		return err
	}
	featureAbs := *feature
	if !filepath.IsAbs(featureAbs) {
		featureAbs = filepath.Join(abs, featureAbs)
	}
	featureAbs, err = filepath.EvalSymlinks(featureAbs)
	if err != nil {
		return fmt.Errorf("feature directory: %w", err)
	}
	permissionPath, err := filepath.Abs(*permissions)
	if err != nil {
		return err
	}
	// The same classifier owns both lexical/resolved permissions. Feature linkage
	// is checked against the configured feature root, never inferred from ownership.
	checker := func(path string) error {
		cmd := exec.Command("bash", "-c", `. "$1"; kaba_load_config; [ "$(cd "$4" && pwd -P)" = "$(cd "$KABA_REPO_ROOT" && pwd -P)" ] || { echo 'scaffold root must be the repository root' >&2; exit 1; }; configured="$(cd "$KABA_REPO_ROOT/${KABA_FEATURE_DIR%/}" && pwd -P)" || exit 1; [ "$(dirname "$2")" = "$configured" ] || { echo 'scaffold feature is outside configured feature root' >&2; exit 1; }; if [ -n "$3" ]; then [ "$(kaba_classify_path "$3")" = test ] || { echo 'scaffold source must be test-owned' >&2; exit 1; }; fi`, "scaffold", permissionPath, featureAbs, path, abs)
		cmd.Dir = abs
		b, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("scaffold ownership: %s: %w", strings.TrimSpace(string(b)), err)
		}
		return nil
	}
	if err := checker(""); err != nil {
		return err
	}
	listArgs := []string{"list", "-e", "-json", "-mod=readonly"}
	if *tags != "" {
		listArgs = append(listArgs, "-tags", *tags)
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
	listArgs = append(listArgs, selected...)
	cmd := exec.Command(*goBin, listArgs...)
	cmd.Dir = abs
	cmd.Stderr = os.Stderr
	data, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("scaffold go list: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	pkgs := []listedPackage{}
	for {
		var p listedPackage
		if err := decoder.Decode(&p); err == io.EOF {
			break
		} else if err != nil {
			return err
		}
		if p.Error != nil {
			return fmt.Errorf("package %s: %s", p.ImportPath, p.Error.Err)
		}
		pkgs = append(pkgs, p)
	}
	if len(pkgs) == 0 {
		return fmt.Errorf("package selection matched no packages")
	}
	result, err := buildScaffold(abs, featureAbs, *output, pkgs, checker)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}

func insideRoot(root, path string) bool {
	rel, err := filepath.Rel(root, path)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}
func nodeText(fs *token.FileSet, n ast.Node) string {
	var b bytes.Buffer
	_ = printer.Fprint(&b, fs, n)
	return b.String()
}
func receiverName(e ast.Expr) string {
	switch x := e.(type) {
	case *ast.Ident:
		return x.Name
	case *ast.StarExpr:
		return receiverName(x.X)
	case *ast.IndexExpr:
		return receiverName(x.X)
	case *ast.IndexListExpr:
		return receiverName(x.X)
	}
	return ""
}
func functionKey(f *ast.FuncDecl) string {
	if f.Recv != nil && len(f.Recv.List) == 1 {
		return receiverName(f.Recv.List[0].Type) + "." + f.Name.Name
	}
	return f.Name.Name
}
func zeroExpression(e ast.Expr) bool {
	switch x := e.(type) {
	case *ast.ParenExpr:
		return zeroExpression(x.X)
	case *ast.Ident:
		return x.Name == "nil" || x.Name == "false"
	case *ast.UnaryExpr:
		return (x.Op == token.ADD || x.Op == token.SUB) && zeroExpression(x.X)
	case *ast.BasicLit:
		if x.Kind == token.STRING {
			v, err := strconv.Unquote(x.Value)
			return err == nil && v == ""
		}
		v := constant.MakeFromLiteral(x.Value, x.Kind, 0)
		return v.Kind() != constant.Unknown && constant.Compare(v, token.EQL, constant.MakeInt64(0))
	}
	return false
}
func minimalBody(f *ast.FuncDecl) bool {
	if f.Body == nil {
		return false
	}
	// nil and false must denote the predeclared zero values, not parameters.
	for _, list := range []*ast.FieldList{f.Recv, f.Type.Params, f.Type.Results} {
		if list == nil {
			continue
		}
		for _, field := range list.List {
			for _, name := range field.Names {
				if name.Name == "nil" || name.Name == "false" {
					return false
				}
			}
		}
	}
	count := 0
	named := true
	if f.Type.Results != nil {
		for _, r := range f.Type.Results.List {
			n := len(r.Names)
			if n == 0 {
				n = 1
				named = false
			}
			count += n
		}
	}
	if count == 0 {
		return len(f.Body.List) == 0
	}
	if len(f.Body.List) == 0 {
		return false
	}
	ret, ok := f.Body.List[len(f.Body.List)-1].(*ast.ReturnStmt)
	if !ok {
		return false
	}
	if len(f.Body.List) == 1 {
		if len(ret.Results) == 0 {
			return named
		}
		if len(ret.Results) != count {
			return false
		}
		for _, e := range ret.Results {
			if !zeroExpression(e) {
				return false
			}
		}
		return true
	}
	names := map[string]bool{}
	for _, stmt := range f.Body.List[:len(f.Body.List)-1] {
		d, ok := stmt.(*ast.DeclStmt)
		if !ok {
			return false
		}
		g, ok := d.Decl.(*ast.GenDecl)
		if !ok || g.Tok != token.VAR {
			return false
		}
		for _, sp := range g.Specs {
			v, ok := sp.(*ast.ValueSpec)
			if !ok || v.Type == nil || len(v.Values) != 0 {
				return false
			}
			for _, n := range v.Names {
				if n.Name == "_" || names[n.Name] {
					return false
				}
				names[n.Name] = true
			}
		}
	}
	if len(ret.Results) != count {
		return false
	}
	for _, e := range ret.Results {
		i, ok := e.(*ast.Ident)
		if !ok || !names[i.Name] {
			return false
		}
	}
	return true
}
func scaffoldImportNames(file *ast.File) (map[string]*ast.ImportSpec, error) {
	result := map[string]*ast.ImportSpec{}
	for _, imp := range file.Imports {
		p, err := strconv.Unquote(imp.Path.Value)
		if err != nil {
			return nil, err
		}
		alias := filepath.Base(p)
		if imp.Name != nil {
			alias = imp.Name.Name
		}
		if p == "C" || alias == "_" || alias == "." {
			return nil, fmt.Errorf("side-effect, dot and cgo imports are forbidden in scaffolds")
		}
		if result[alias] != nil {
			return nil, fmt.Errorf("duplicate scaffold import alias %s", alias)
		}
		result[alias] = imp
	}
	return result, nil
}
func usedImports(nodes []ast.Node, imports map[string]*ast.ImportSpec) []*ast.ImportSpec {
	used := map[string]bool{}
	for _, node := range nodes {
		ast.Inspect(node, func(n ast.Node) bool {
			if s, ok := n.(*ast.SelectorExpr); ok {
				if i, ok := s.X.(*ast.Ident); ok && imports[i.Name] != nil {
					used[i.Name] = true
				}
			}
			return true
		})
	}
	names := []string{}
	for n := range used {
		names = append(names, n)
	}
	sort.Strings(names)
	result := []*ast.ImportSpec{}
	for _, n := range names {
		result = append(result, imports[n])
	}
	return result
}
func fieldNames(field *ast.Field) ([]string, error) {
	if len(field.Names) > 0 {
		names := []string{}
		for _, n := range field.Names {
			if n.Name == "_" {
				return nil, fmt.Errorf("blank fields are unsupported")
			}
			names = append(names, n.Name)
		}
		return names, nil
	}
	e := field.Type
	if p, ok := e.(*ast.StarExpr); ok {
		e = p.X
	}
	switch x := e.(type) {
	case *ast.Ident:
		return []string{x.Name}, nil
	case *ast.SelectorExpr:
		return []string{x.Sel.Name}, nil
	}
	return nil, fmt.Errorf("unsupported embedded scaffold field")
}

// Existing source follows the Go grammar, not the narrower scaffold grammar.
// Blank fields introduce no selector; instantiated embedded types introduce the
// underlying type name just like ordinary embedded types.
func existingFieldNames(field *ast.Field) []string {
	names := []string{}
	for _, name := range field.Names {
		if name.Name != "_" {
			names = append(names, name.Name)
		}
	}
	if len(field.Names) != 0 {
		return names
	}
	e := field.Type
	for {
		switch x := e.(type) {
		case *ast.StarExpr:
			e = x.X
		case *ast.IndexExpr:
			e = x.X
		case *ast.IndexListExpr:
			e = x.X
		case *ast.Ident:
			return []string{x.Name}
		case *ast.SelectorExpr:
			return []string{x.Sel.Name}
		default:
			return names
		}
	}
}

func buildScaffold(root, feature, output string, pkgs []listedPackage, check func(string) error) (scaffoldResult, error) {
	result := scaffoldResult{Files: []scaffoldFile{}, Packages: []string{}}
	var err error
	root, err = filepath.EvalSymlinks(root)
	if err != nil {
		return result, err
	}
	feature, err = filepath.EvalSymlinks(feature)
	if err != nil {
		return result, err
	}
	if !insideRoot(root, feature) || feature == root {
		return result, fmt.Errorf("feature outside repository")
	}
	output, err = filepath.EvalSymlinks(output)
	if err != nil {
		return result, err
	}
	if insideRoot(root, output) {
		return result, fmt.Errorf("scaffold output must be outside production repository")
	}
	entries, err := os.ReadDir(output)
	if err != nil {
		return result, err
	}
	if len(entries) != 0 {
		return result, fmt.Errorf("stale scaffold output: runner temporary directory must be empty")
	}
	fs := token.NewFileSet()
	generated := map[string][]byte{}
	edits := map[string][]scaffoldEdit{}
	production := map[string]scaffoldSource{}
	extraImports := map[string]map[string]*ast.ImportSpec{}
	for _, pkg := range pkgs {
		pkg.Dir, err = filepath.EvalSymlinks(pkg.Dir)
		if err != nil {
			return result, err
		}
		if !insideRoot(root, pkg.Dir) {
			return result, fmt.Errorf("package %s is outside repository", pkg.ImportPath)
		}
		names := map[string]bool{}
		types := map[string]scaffoldType{}
		packageName := ""
		for _, name := range append(append([]string{}, pkg.GoFiles...), pkg.CgoFiles...) {
			path := filepath.Join(pkg.Dir, name)
			data, err := os.ReadFile(path)
			if err != nil {
				return result, err
			}
			file, err := parser.ParseFile(fs, path, data, parser.ParseComments)
			if err != nil {
				return result, err
			}
			packageName = file.Name.Name
			src := scaffoldSource{path, data, file}
			production[path] = src
			for _, d := range file.Decls {
				switch x := d.(type) {
				case *ast.FuncDecl:
					names[functionKey(x)] = true
				case *ast.GenDecl:
					for _, sp := range x.Specs {
						switch y := sp.(type) {
						case *ast.TypeSpec:
							names[y.Name.Name] = true
							types[y.Name.Name] = scaffoldType{y, src}
							if structure, ok := y.Type.(*ast.StructType); ok {
								for _, field := range structure.Fields.List {
									fields := existingFieldNames(field)
									for _, field := range fields {
										names[y.Name.Name+"."+field] = true
									}
								}
							}
						case *ast.ValueSpec:
							for _, n := range y.Names {
								names[n.Name] = true
							}
						}
					}
				}
			}
		}
		// Test helpers inhabit the same compile scope; a scaffold cannot replace them.
		for _, name := range pkg.TestGoFiles {
			file, err := parser.ParseFile(fs, filepath.Join(pkg.Dir, name), nil, 0)
			if err != nil {
				return result, err
			}
			if packageName == "" {
				packageName = file.Name.Name
			}
			for _, d := range file.Decls {
				switch x := d.(type) {
				case *ast.FuncDecl:
					names[functionKey(x)] = true
				case *ast.GenDecl:
					for _, sp := range x.Specs {
						switch y := sp.(type) {
						case *ast.TypeSpec:
							names[y.Name.Name] = true
						case *ast.ValueSpec:
							for _, n := range y.Names {
								names[n.Name] = true
							}
						}
					}
				}
			}
		}
		dir := filepath.Join(pkg.Dir, "testdata", "kaba", filepath.Base(feature))
		sources, err := filepath.Glob(filepath.Join(dir, "*.go"))
		if err != nil {
			return result, err
		}
		if len(sources) == 0 {
			continue
		}
		result.Packages = append(result.Packages, pkg.ImportPath)
		requested := map[string]bool{}
		for sourceIndex, path := range sources {
			rel, _ := filepath.Rel(root, path)
			if err := check(filepath.ToSlash(rel)); err != nil {
				return result, err
			}
			resolved, err := filepath.EvalSymlinks(path)
			if err != nil {
				return result, err
			}
			if !insideRoot(root, resolved) {
				return result, fmt.Errorf("scaffold source outside repository")
			}
			info, err := os.Lstat(path)
			if err != nil {
				return result, err
			}
			if !info.Mode().IsRegular() {
				return result, fmt.Errorf("scaffold sources must be regular files")
			}
			data, err := os.ReadFile(path)
			if err != nil {
				return result, err
			}
			file, err := parser.ParseFile(fs, path, data, parser.ParseComments)
			if err != nil {
				return result, err
			}
			if packageName == "" {
				packageName = file.Name.Name
			}
			if file.Name.Name != packageName {
				return result, fmt.Errorf("scaffold package %s does not match production package %s", file.Name.Name, packageName)
			}
			for _, g := range file.Comments {
				for _, c := range g.List {
					if strings.HasPrefix(c.Text, "//go:") || strings.HasPrefix(c.Text, "// +build") || strings.HasPrefix(c.Text, "//line") || strings.HasPrefix(c.Text, "/*line") {
						return result, fmt.Errorf("compiler directives are unsupported in scaffold sources")
					}
				}
			}
			imports, err := scaffoldImportNames(file)
			if err != nil {
				return result, err
			}
			newDecls := []ast.Decl{}
			newNodes := []ast.Node{}
			for _, decl := range file.Decls {
				switch d := decl.(type) {
				case *ast.FuncDecl:
					key := functionKey(d)
					if d.Recv == nil && gotypes.Universe.Lookup(d.Name.Name) != nil {
						return result, fmt.Errorf("scaffold declaration shadows predeclared identifier %s", d.Name.Name)
					}
					shadowed := false
					ast.Inspect(d.Body, func(n ast.Node) bool {
						if i, ok := n.(*ast.Ident); ok && (i.Name == "nil" || i.Name == "false") && names[i.Name] {
							shadowed = true
						}
						return true
					})
					if shadowed {
						return result, fmt.Errorf("scaffold zero value is shadowed by an existing declaration")
					}
					if d.Name.Name == "init" || d.Name.Name == "_" || d.Name.Name == "nil" || d.Name.Name == "false" || !minimalBody(d) {
						return result, fmt.Errorf("scaffold %s: %s must have a minimal zero body, without side effects", rel, d.Name.Name)
					}
					if names[key] || requested[key] {
						return result, fmt.Errorf("duplicate/stale scaffold declaration %s", key)
					}
					if d.Recv != nil {
						if existing, ok := types[receiverName(d.Recv.List[0].Type)]; ok {
							if structure, ok := existing.spec.Type.(*ast.StructType); ok {
								for _, field := range structure.Fields.List {
									fields := existingFieldNames(field)
									for _, field := range fields {
										if field == d.Name.Name {
											return result, fmt.Errorf("scaffold method conflicts with existing field %s", key)
										}
									}
								}
							}
						}
					}
					requested[key] = true
					newDecls = append(newDecls, d)
					newNodes = append(newNodes, d)
				case *ast.GenDecl:
					if d.Tok == token.IMPORT {
						continue
					}
					if d.Tok != token.TYPE {
						return result, fmt.Errorf("scaffolds permit types and minimal functions only")
					}
					for _, sp := range d.Specs {
						typ := sp.(*ast.TypeSpec)
						badType := false
						ast.Inspect(typ, func(n ast.Node) bool {
							switch n.(type) {
							case *ast.CallExpr, *ast.FuncLit:
								badType = true
							}
							return true
						})
						if badType {
							return result, fmt.Errorf("executable scaffold type expression")
						}
						name := typ.Name.Name
						if name == "_" || gotypes.Universe.Lookup(name) != nil {
							return result, fmt.Errorf("unsupported scaffold type name %s", name)
						}
						if requested[name] {
							return result, fmt.Errorf("duplicate scaffold type %s", name)
						}
						requested[name] = true
						if existing, ok := types[name]; ok {
							old, oldOK := existing.spec.Type.(*ast.StructType)
							add, addOK := typ.Type.(*ast.StructType)
							if !oldOK || !addOK || typ.Assign.IsValid() || typ.TypeParams != nil || existing.spec.TypeParams != nil {
								return result, fmt.Errorf("existing scaffold type %s only permits additive struct fields", name)
							}
							if len(add.Fields.List) == 0 {
								return result, fmt.Errorf("existing scaffold struct %s has no additive fields", name)
							}
							fieldSet := map[string]bool{}
							for _, f := range old.Fields.List {
								ns := existingFieldNames(f)
								for _, n := range ns {
									fieldSet[n] = true
									requested[name+"."+n] = true
								}
							}
							text := "\n"
							nodes := []ast.Node{}
							for _, f := range add.Fields.List {
								ns, err := fieldNames(f)
								if err != nil {
									return result, err
								}
								for _, n := range ns {
									if fieldSet[n] || names[name+"."+n] || requested[name+"."+n] {
										return result, fmt.Errorf("duplicate existing scaffold field %s.%s", name, n)
									}
									fieldSet[n] = true
									requested[name+"."+n] = true
								}
								text += string(data[fs.Position(f.Pos()).Offset:fs.Position(f.End()).Offset]) + "\n"
								nodes = append(nodes, f)
							}
							target := existing.source.path
							edits[target] = append(edits[target], scaffoldEdit{fs.Position(old.Fields.Closing).Offset, text})
							if extraImports[target] == nil {
								extraImports[target] = map[string]*ast.ImportSpec{}
							}
							for _, imp := range usedImports(nodes, imports) {
								alias := filepath.Base(strings.Trim(imp.Path.Value, `"`))
								if imp.Name != nil {
									alias = imp.Name.Name
								}
								if previous := extraImports[target][alias]; previous != nil && previous.Path.Value != imp.Path.Value {
									return result, fmt.Errorf("conflicting field import %s", alias)
								}
								extraImports[target][alias] = imp
							}
						} else {
							if names[name] {
								return result, fmt.Errorf("duplicate/stale scaffold declaration %s", name)
							}
							if structure, ok := typ.Type.(*ast.StructType); ok {
								fields := map[string]bool{}
								for _, field := range structure.Fields.List {
									fieldNames, err := fieldNames(field)
									if err != nil {
										return result, err
									}
									for _, field := range fieldNames {
										key := name + "." + field
										if fields[field] || requested[key] {
											return result, fmt.Errorf("duplicate scaffold field %s", key)
										}
										fields[field] = true
										requested[key] = true
									}
								}
							}
							newDecls = append(newDecls, &ast.GenDecl{Tok: token.TYPE, Specs: []ast.Spec{typ}})
							newNodes = append(newNodes, typ)
						}
					}
				default:
					return result, fmt.Errorf("unsupported scaffold declaration")
				}
			}
			// Type expressions cannot carry calls or executable literal bodies either.
			badType := false
			for _, n := range newNodes {
				if d, ok := n.(*ast.FuncDecl); ok {
					n = d.Type
				}
				ast.Inspect(n, func(n ast.Node) bool {
					switch n.(type) {
					case *ast.CallExpr, *ast.FuncLit:
						badType = true
					}
					return true
				})
			}
			if badType {
				return result, fmt.Errorf("executable scaffold type expression")
			}
			if len(newDecls) > 0 {
				virtual := filepath.Join(pkg.Dir, fmt.Sprintf("zz_kaba_scaffold_%03d.go", sourceIndex))
				if _, err := os.Lstat(virtual); !os.IsNotExist(err) {
					return result, fmt.Errorf("scaffold overlay collision at %s", virtual)
				}
				var b strings.Builder
				b.WriteString("package " + packageName + "\n")
				used := usedImports(newNodes, imports)
				if len(used) > 0 {
					b.WriteString("import (\n")
					for _, imp := range used {
						b.WriteString(nodeText(fs, imp) + "\n")
					}
					b.WriteString(")\n")
				}
				for _, d := range newDecls {
					b.WriteString(nodeText(fs, d) + "\n")
				}
				generated[virtual] = []byte(b.String())
			}
			hash := sha256.Sum256(data)
			result.Files = append(result.Files, scaffoldFile{filepath.ToSlash(rel), hex.EncodeToString(hash[:]), pkg.ImportPath})
		}
	}
	for path, insertions := range edits {
		src := production[path]
		existingImports := map[string]*ast.ImportSpec{}
		for _, imp := range src.file.Imports {
			p, _ := strconv.Unquote(imp.Path.Value)
			alias := filepath.Base(p)
			if imp.Name != nil {
				alias = imp.Name.Name
			}
			existingImports[alias] = imp
		}
		addition := "\nimport (\n"
		hasAddition := false
		aliases := []string{}
		for alias := range extraImports[path] {
			aliases = append(aliases, alias)
		}
		sort.Strings(aliases)
		for _, alias := range aliases {
			imp := extraImports[path][alias]
			if existing := existingImports[alias]; existing != nil {
				if existing.Path.Value != imp.Path.Value {
					return result, fmt.Errorf("field import conflicts with production alias %s", alias)
				}
				continue
			}
			for oldAlias, existing := range existingImports {
				if existing.Path.Value == imp.Path.Value && oldAlias != alias {
					return result, fmt.Errorf("field import requires existing production alias %s", oldAlias)
				}
			}
			addition += nodeText(fs, imp) + "\n"
			hasAddition = true
		}
		addition += ")\n"
		if hasAddition {
			insertions = append(insertions, scaffoldEdit{fs.Position(src.file.Name.End()).Offset, addition})
		}
		sort.Slice(insertions, func(i, j int) bool { return insertions[i].offset > insertions[j].offset })
		data := src.data
		for _, e := range insertions {
			data = append(append(append([]byte{}, data[:e.offset]...), []byte(e.text)...), data[e.offset:]...)
		}
		generated[path] = data
	}
	if len(result.Files) == 0 {
		return result, nil
	}
	sort.Strings(result.Packages)
	sort.Slice(result.Files, func(i, j int) bool { return result.Files[i].Path < result.Files[j].Path })
	paths := []string{}
	for path := range generated {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	overlay := struct{ Replace map[string]string }{map[string]string{}}
	for i, path := range paths {
		dest := filepath.Join(output, fmt.Sprintf("source-%03d.go", i))
		if err := os.WriteFile(dest, generated[path], 0600); err != nil {
			return result, err
		}
		overlay.Replace[path] = dest
	}
	overlayPath := filepath.Join(output, "overlay.json")
	data, err := json.Marshal(overlay)
	if err != nil {
		return result, err
	}
	if err := os.WriteFile(overlayPath, data, 0600); err != nil {
		return result, err
	}
	result.Overlay = &overlayPath
	return result, nil
}
