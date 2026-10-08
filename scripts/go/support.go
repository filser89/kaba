package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
)

type supportDeclaration struct {
	node       ast.Node
	imports    []*ast.ImportSpec
	directives string
}

func testSupport(file *ast.File, alias string) map[string]supportDeclaration {
	out := map[string]supportDeclaration{}
	directives := ""
	for _, group := range file.Comments {
		for _, comment := range group.List {
			if strings.HasPrefix(comment.Text, "//go:") || strings.HasPrefix(comment.Text, "// +build") || strings.HasPrefix(comment.Text, "//line ") {
				directives += comment.Text + "\n"
			}
		}
	}
	blanks := 0
	add := func(name string, node ast.Node) {
		if name == "_" {
			name = fmt.Sprintf("blank:%d", blanks)
			blanks++
		}
		out[name] = supportDeclaration{node, file.Imports, directives}
	}
	initializers := 0
	variableInitializers := 0
	for _, decl := range file.Decls {
		switch value := decl.(type) {
		case *ast.FuncDecl:
			if value.Name.Name == "_" {
				add("_", value)
				continue
			}
			if value.Recv != nil {
				add("method:"+value.Name.Name+":"+receiverTypeName(value.Recv.List[0].Type), value)
				continue
			}
			if value.Name.Name == "init" {
				add(fmt.Sprintf("init:%d", initializers), value)
				initializers++
				continue
			}
			if !testFunction(value, alias) {
				add(value.Name.Name, value)
			}
		case *ast.GenDecl:
			if value.Tok == token.IMPORT {
				continue
			}
			for _, spec := range value.Specs {
				node := &ast.GenDecl{Tok: value.Tok, Specs: []ast.Spec{spec}}
				if value.Tok == token.CONST {
					// Implicit expressions and iota depend on the complete declaration.
					node = value
				}
				switch value := spec.(type) {
				case *ast.ValueSpec:
					for _, name := range value.Names {
						add(name.Name, node)
					}
					if node.Tok == token.VAR && len(value.Values) > 0 {
						add(fmt.Sprintf("var-init:%d", variableInitializers), node)
						variableInitializers++
					}
				case *ast.TypeSpec:
					add(value.Name.Name, value)
				}
			}
		}
	}
	return out
}

func receiverTypeName(expr ast.Expr) string {
	switch value := expr.(type) {
	case *ast.Ident:
		return value.Name
	case *ast.StarExpr:
		return receiverTypeName(value.X)
	case *ast.IndexExpr:
		return receiverTypeName(value.X)
	case *ast.IndexListExpr:
		return receiverTypeName(value.X)
	case *ast.ParenExpr:
		return receiverTypeName(value.X)
	}
	return "unsupported"
}
func exprNodes(rows []ast.Expr) []ast.Node {
	out := []ast.Node{}
	for _, row := range rows {
		out = append(out, row)
	}
	return out
}
func (s *sourceScanner) registration(stmt ast.Stmt) bool {
	ex, ok := stmt.(*ast.ExprStmt)
	if !ok {
		return false
	}
	for receiver := range s.receivers {
		if runCall(ex.X, receiver) != nil {
			return true
		}
	}
	return false
}
func (s *sourceScanner) dependencies(nodes []ast.Node, support map[string]supportDeclaration) []string {
	seen := map[string]bool{}
	expanded := map[string]bool{}
	var inspect func(ast.Node)
	var collect func(string)
	collect = func(name string) {
		if expanded[name] {
			return
		}
		expanded[name] = true
		// Include direct method-name candidates and methods on a referenced
		// receiver type: interfaces can invoke them without naming the method.
		for key := range support {
			if strings.HasPrefix(key, "method:"+name+":") ||
				(strings.HasPrefix(key, "method:") && strings.HasSuffix(key, ":"+name)) {
				collect(key)
			}
		}
		decl, ok := support[name]
		if !ok {
			return
		}
		seen[name] = true
		inspect(decl.node)
	}
	inspect = func(node ast.Node) {
		ast.Inspect(node, func(node ast.Node) bool {
			if node == nil {
				return false
			}
			if s.tables[node] {
				if table, ok := node.(*ast.CompositeLit); ok {
					inspect(table.Type)
				}
				return false
			}
			if body, ok := node.(*ast.BlockStmt); ok {
				for _, stmt := range body.List {
					if !s.registration(stmt) {
						inspect(stmt)
					}
				}
				return false
			}
			if ident, ok := node.(*ast.Ident); ok {
				collect(ident.Name)
			}
			return true
		})
	}
	for _, node := range nodes {
		inspect(node)
	}
	collect("TestMain")
	for name := range support {
		if implicitSupport(name) {
			collect(name)
		}
	}
	names := []string{}
	for name := range seen {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// The index contains test support only: real production changes must not change
// locked test digests. Internal and external test packages have separate scopes.
func scanPackage(pkg, dir, rel string, files []string) ([]Record, error) {
	type sourceFile struct {
		name    string
		content []byte
		parsed  *ast.File
	}
	sources := []sourceFile{}
	index := map[string]map[string]supportDeclaration{}
	for _, name := range files {
		content, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, err
		}
		parsed, err := parser.ParseFile(token.NewFileSet(), name, content, parser.ParseComments)
		if err != nil {
			return nil, err
		}
		alias := "testing"
		for _, imp := range parsed.Imports {
			if imp.Path.Value == `"testing"` && imp.Name != nil {
				alias = imp.Name.Name
			}
		}
		scope := index[parsed.Name.Name]
		if scope == nil {
			scope = map[string]supportDeclaration{}
			index[parsed.Name.Name] = scope
		}
		for key, value := range testSupport(parsed, alias) {
			if implicitSupport(key) || strings.HasPrefix(key, "blank:") {
				prefix, suffix, _ := strings.Cut(key, ":")
				key = prefix + ":" + name + ":" + suffix
			}
			if _, exists := scope[key]; exists {
				return nil, fmt.Errorf("%s: ambiguous test support declaration %s", name, key)
			}
			scope[key] = value
		}
		sources = append(sources, sourceFile{name, content, parsed})
	}
	// Both package scopes are linked into one executable. Every initializer and
	// TestMain dependency can affect tests in either scope.
	shared := []any{}
	scopeNames := []string{}
	for name := range index {
		scopeNames = append(scopeNames, name)
	}
	sort.Strings(scopeNames)
	scanner := &sourceScanner{}
	for _, name := range scopeNames {
		scope := index[name]
		for _, key := range scanner.dependencies(nil, scope) {
			decl := scope[key]
			shared = append(shared, []any{name, key, decl.directives, scanner.structural(reflect.ValueOf(decl.node)), scanner.structural(reflect.ValueOf(decl.imports))})
		}
	}
	out := []Record{}
	for _, source := range sources {
		if !strings.HasSuffix(source.name, "_test.go") {
			continue
		}
		records, err := scanSource(pkg, filepath.ToSlash(filepath.Join(rel, source.name)), source.content, index[source.parsed.Name.Name])
		if err != nil {
			return nil, err
		}
		for i := range records {
			records[i].Digest = structuralHash([]any{records[i].Digest, shared})
		}
		out = append(out, records...)
	}
	return out, nil
}

func implicitSupport(name string) bool {
	return strings.HasPrefix(name, "init:") || strings.HasPrefix(name, "var-init:")
}

func structuralHash(value any) string {
	data, _ := json.Marshal(value)
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// Ownership is decided by the shared shell classifier, never by directory-name
// guesses. Restrict candidates to active Go files returned by the Go build tool.
func ownedGoSources(root, permissions string, graph map[string]listedPackage) (map[string][]string, error) {
	result := map[string][]string{}
	for path, pkg := range graph {
		rel, err := filepath.Rel(root, pkg.Dir)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			continue
		}
		for _, file := range append(append([]string{}, pkg.GoFiles...), pkg.CgoFiles...) {
			relative := filepath.ToSlash(filepath.Join(rel, file))
			cmd := exec.Command("bash", permissions, "classify", relative)
			cmd.Dir, cmd.Stderr = root, os.Stderr
			owner, err := cmd.Output()
			if err != nil {
				return nil, fmt.Errorf("classify test support %s: %w", relative, err)
			}
			if strings.TrimSpace(string(owner)) == "test" {
				result[path] = append(result[path], file)
			}
		}
	}
	return result, nil
}

// Imported support is conservative at package granularity. Traverse production
// packages to reach transitive test-owned support, but never hash production ASTs.
func importedSupportDigest(root string, selected listedPackage, graph map[string]listedPackage, owned map[string][]string) (string, error) {
	seen := map[string]bool{}
	files := []string{}
	var visit func(string)
	visit = func(path string) {
		if seen[path] {
			return
		}
		seen[path] = true
		pkg, ok := graph[path]
		if !ok {
			return
		}
		for _, file := range owned[path] {
			files = append(files, filepath.Join(pkg.Dir, file))
		}
		for _, dependency := range pkg.Imports {
			visit(dependency)
		}
	}
	for _, path := range append(append(append([]string{}, selected.Imports...), selected.TestImports...), selected.XTestImports...) {
		visit(path)
	}
	sort.Strings(files)
	parts := []any{}
	scanner := &sourceScanner{}
	for _, file := range files {
		parsed, err := parser.ParseFile(token.NewFileSet(), file, nil, parser.ParseComments)
		if err != nil {
			return "", err
		}
		rel, _ := filepath.Rel(root, file)
		directives := ""
		for _, group := range parsed.Comments {
			for _, comment := range group.List {
				if strings.HasPrefix(comment.Text, "//go:") || strings.HasPrefix(comment.Text, "// +build") || strings.HasPrefix(comment.Text, "//line ") || strings.HasPrefix(comment.Text, "/*line ") {
					directives += comment.Text + "\n"
				}
			}
		}
		// Declarations cover imports and compiler semantics while avoiding the
		// parser's ancillary File.Unresolved list, which is not source semantics.
		parts = append(parts, []any{filepath.ToSlash(rel), directives, scanner.structural(reflect.ValueOf(parsed.Decls))})
	}
	if len(parts) == 0 {
		return "", nil
	}
	return structuralHash(parts), nil
}
