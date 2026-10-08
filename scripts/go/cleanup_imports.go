package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/importer"
	"go/parser"
	"go/scanner"
	"go/token"
	"go/types"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// Import usage is bound in the original, compiling package. Removing a test can
// strand an import, but identifiers with the same spelling in another scope must
// not keep it alive. Export data also resolves dot imports and real package names.
type cleanupImportResolver struct {
	root, goBin, tags string
	files             map[string]*cleanupImportFile
}
type cleanupImportFile struct {
	file *ast.File
	fset *token.FileSet
	info *types.Info
}
type cleanupListedPackage struct {
	ImportPath, Name, Dir, ForTest, Export string
	CompiledGoFiles                        []string
	ImportMap                              map[string]string
}

func (r *cleanupImportResolver) load(path string) (*cleanupImportFile, error) {
	absolute := filepath.Join(r.root, path)
	if f := r.files[absolute]; f != nil {
		return f, nil
	}
	args := []string{"list", "-json", "-deps", "-test", "-export", "-compiled", "-mod=readonly"}
	if r.tags != "" {
		args = append(args, "-tags", r.tags)
	}
	args = append(args, "./"+filepath.ToSlash(filepath.Dir(path)))
	cmd := exec.Command(r.goBin, args...)
	cmd.Dir = r.root
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	data, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("import usage go list: %w: %s", err, stderr.String())
	}
	exports := map[string]string{}
	var selected *cleanupListedPackage
	decoder := json.NewDecoder(bytes.NewReader(data))
	for {
		var pkg cleanupListedPackage
		if err := decoder.Decode(&pkg); err == io.EOF {
			break
		} else if err != nil {
			return nil, err
		}
		exports[pkg.ImportPath] = pkg.Export
		if pkg.ForTest == "" {
			continue
		}
		for _, name := range pkg.CompiledGoFiles {
			if !filepath.IsAbs(name) {
				name = filepath.Join(pkg.Dir, name)
			}
			if filepath.Clean(name) == absolute {
				copy := pkg
				selected = &copy
				break
			}
		}
	}
	if selected == nil {
		return nil, fmt.Errorf("%s is not in the selected Go test build", path)
	}
	fs := token.NewFileSet()
	var files []*ast.File
	for _, name := range selected.CompiledGoFiles {
		if !filepath.IsAbs(name) {
			name = filepath.Join(selected.Dir, name)
		}
		file, err := parser.ParseFile(fs, name, nil, parser.ParseComments)
		if err != nil {
			return nil, err
		}
		files = append(files, file)
	}
	info := &types.Info{Uses: map[*ast.Ident]types.Object{}, Defs: map[*ast.Ident]types.Object{}, Implicits: map[ast.Node]types.Object{}, Scopes: map[ast.Node]*types.Scope{}}
	config := types.Config{
		Sizes: types.SizesFor("gc", runtime.GOARCH),
		Importer: importer.ForCompiler(fs, "gc", func(path string) (io.ReadCloser, error) {
			if mapped := selected.ImportMap[path]; mapped != "" {
				path = mapped
			}
			export := exports[path]
			if export == "" {
				return nil, fmt.Errorf("no export data for %s", path)
			}
			return os.Open(export)
		}),
	}
	if _, err := config.Check(selected.ImportPath, fs, files, info); err != nil {
		return nil, fmt.Errorf("import usage type check: %w", err)
	}
	if r.files == nil {
		r.files = map[string]*cleanupImportFile{}
	}
	for _, file := range files {
		r.files[fs.PositionFor(file.Pos(), false).Filename] = &cleanupImportFile{file, fs, info}
	}
	if f := r.files[absolute]; f != nil {
		return f, nil
	}
	return nil, fmt.Errorf("no import usage for %s", path)
}

func (r *cleanupImportResolver) removals(path string, src []byte, edits []goEdit) ([]goEdit, error) {
	source, err := r.load(path)
	if err != nil {
		return nil, err
	}
	offset := func(pos token.Pos) int { return source.fset.PositionFor(pos, false).Offset }
	deleted := func(pos token.Pos) bool {
		at := offset(pos)
		for _, edit := range edits {
			if at >= edit.Start && at < edit.End {
				return true
			}
		}
		return false
	}
	// Selector members are not unqualified references through a dot import.
	selectorNames := map[*ast.Ident]bool{}
	ast.Inspect(source.file, func(node ast.Node) bool {
		if selector, ok := node.(*ast.SelectorExpr); ok {
			selectorNames[selector.Sel] = true
		}
		return true
	})
	fileScope := source.info.Scopes[source.file]
	remove := map[*ast.ImportSpec]bool{}
	for _, imp := range source.file.Imports {
		var name *types.PkgName
		if imp.Name != nil {
			name, _ = source.info.Defs[imp.Name].(*types.PkgName)
		} else {
			name, _ = source.info.Implicits[imp].(*types.PkgName)
		}
		if name == nil {
			return nil, fmt.Errorf("unresolved import %s", imp.Path.Value)
		}
		if name.Name() == "_" {
			continue
		}
		used, retained := false, false
		for ident, obj := range source.info.Uses {
			if ident.Pos() < source.file.Pos() || ident.Pos() >= source.file.End() {
				continue
			}
			match := obj == name
			if name.Name() == "." {
				match = !selectorNames[ident] && obj.Pkg() == name.Imported() && fileScope.Lookup(ident.Name) == obj
			}
			if match {
				used = true
				if !deleted(ident.Pos()) {
					retained = true
					break
				}
			}
		}
		if used && !retained {
			remove[imp] = true
		}
	}
	var result []goEdit
	for _, decl := range source.file.Decls {
		imports, ok := decl.(*ast.GenDecl)
		if !ok || imports.Tok != token.IMPORT {
			continue
		}
		// Empty grouped imports are legal; preserve their comments/directives.
		if !imports.Lparen.IsValid() && len(imports.Specs) == 1 && remove[imports.Specs[0].(*ast.ImportSpec)] {
			result = append(result, goEdit{offset(imports.Pos()), offset(imports.End())})
		} else {
			for _, spec := range imports.Specs {
				if remove[spec.(*ast.ImportSpec)] {
					result = append(result, goEdit{offset(spec.Pos()), offset(spec.End())})
					// An explicit separator belongs to the deleted spec. Keep intervening
					// comments byte-for-byte, including directives.
					end := offset(spec.End())
					tokens := token.NewFileSet()
					tokenFile := tokens.AddFile("imports", -1, len(src)-end)
					var scan scanner.Scanner
					scan.Init(tokenFile, src[end:], nil, 0)
					pos, tok, lit := scan.Scan()
					if tok == token.SEMICOLON && lit == ";" {
						at := end + tokenFile.Offset(pos)
						result = append(result, goEdit{at, at + 1})
					}
				}
			}
		}
	}
	return result, nil
}
