package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

type SourceLocation struct {
	Kind        string `json:"kind"`
	StartOffset int    `json:"start_offset"`
	EndOffset   int    `json:"end_offset"`
	RowIndex    *int   `json:"row_index,omitempty"`
}
type Record struct {
	ID              string         `json:"id"`
	FullDescription string         `json:"full_description"`
	FilePath        string         `json:"file_path"`
	LineNumber      int            `json:"line_number"`
	Digest          string         `json:"digest"`
	Package         string         `json:"package"`
	TestName        string         `json:"test_name"`
	ParentID        string         `json:"parent_id"`
	GroupID         string         `json:"group_id"`
	IsGroup         bool           `json:"is_group"`
	Source          SourceLocation `json:"source"`
}
type pendingRecord struct {
	record   Record
	contexts []ast.Node
	rows     []ast.Expr
}
type sourceScanner struct {
	fset                  *token.FileSet
	pkg, path, directives string
	records               []pendingRecord
	names                 map[string]bool
	tables                map[ast.Node]bool
	receivers             map[string]bool
}

func scanSource(pkg, path string, src []byte, additional ...map[string]supportDeclaration) ([]Record, error) {
	fs := token.NewFileSet()
	file, err := parser.ParseFile(fs, path, src, parser.ParseComments)
	if err != nil {
		return nil, err
	}
	s := sourceScanner{fset: fs, pkg: pkg, path: path, names: map[string]bool{}, tables: map[ast.Node]bool{}, receivers: map[string]bool{}}
	// Compiler directives and cgo preambles affect source semantics; ordinary comments do not.
	for _, g := range file.Comments {
		for _, c := range g.List {
			if strings.HasPrefix(c.Text, "//go:") || strings.HasPrefix(c.Text, "// +build") || strings.HasPrefix(c.Text, "//line ") || strings.HasPrefix(c.Text, "/*line ") {
				s.directives += c.Text + "\n"
			}
		}
	}
	testingAlias := "testing"
	suiteAliases := map[string]bool{}
	for _, imp := range file.Imports {
		if imp.Path.Value == `"testing"` && imp.Name != nil {
			testingAlias = imp.Name.Name
		}
		path, _ := strconv.Unquote(imp.Path.Value)
		if path == "github.com/stretchr/testify/suite" {
			alias := "suite"
			if imp.Name != nil {
				alias = imp.Name.Name
			}
			suiteAliases[alias] = true
		}
	}
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if !ok || fn.Body == nil {
			continue
		}
		if strings.HasPrefix(fn.Name.Name, "Example") {
			for _, comments := range file.Comments {
				if comments.Pos() > fn.Pos() && comments.End() < fn.End() {
					for _, line := range strings.Split(comments.Text(), "\n") {
						line = strings.ToLower(strings.TrimSpace(line))
						if strings.HasPrefix(line, "output:") || strings.HasPrefix(line, "unordered output:") {
							return nil, fmt.Errorf("%s: runnable Example tests are not supported by Go inventory", path)
						}
					}
				}
			}
		}
		if strings.HasPrefix(fn.Name.Name, "Fuzz") && fn.Type.Params != nil && len(fn.Type.Params.List) == 1 {
			if ptr, ok := fn.Type.Params.List[0].Type.(*ast.StarExpr); ok {
				if sel, ok := ptr.X.(*ast.SelectorExpr); ok && sel.Sel.Name == "F" {
					return nil, fmt.Errorf("%s: Fuzz tests are not supported by Go inventory", path)
				}
			}
		}
		var unsupported string
		ast.Inspect(fn.Body, func(n ast.Node) bool {
			if sel, ok := n.(*ast.SelectorExpr); ok && sel.Sel.Name == "Run" {
				if x, ok := sel.X.(*ast.Ident); ok && suiteAliases[x.Name] {
					unsupported = "Testify suite registrations"
				}
			}
			return true
		})
		if unsupported != "" {
			return nil, fmt.Errorf("%s: %s are not supported by Go inventory", path, unsupported)
		}
		if !testFunction(fn, testingAlias) && fn.Type.Params != nil {
			for _, param := range fn.Type.Params.List {
				if ptr, ok := param.Type.(*ast.StarExpr); ok {
					if sel, ok := ptr.X.(*ast.SelectorExpr); ok && sel.Sel.Name == "T" {
						for _, name := range param.Names {
							if aliasesReceiver(fn.Body, name.Name) {
								return nil, fmt.Errorf("%s: helper testing receiver aliases are unsupported (%s)", path, fn.Name.Name)
							}
							if hasRun(fn.Body, name.Name) {
								return nil, fmt.Errorf("%s: helper-generated subtests are unsupported (%s)", path, fn.Name.Name)
							}
						}
					}
				}
			}
		}
	}
	for _, d := range file.Decls {
		fn, ok := d.(*ast.FuncDecl)
		if !ok || fn.Recv != nil || !testFunction(fn, testingAlias) {
			continue
		}
		arg := fn.Type.Params.List[0].Names
		if len(arg) != 1 {
			return nil, fmt.Errorf("%s: test parameter must be named", path)
		}
		context := []ast.Node{}
		for _, imp := range file.Imports {
			context = append(context, imp)
		}
		context = append(context, fn.Type, fn.Body)
		if err = s.walk(fn.Body, arg[0].Name, fn.Name.Name, "", fn.Name.Name, context, nil, fn, "function", nil); err != nil {
			return nil, err
		}
	}
	result := make([]Record, 0, len(s.records))
	support := testSupport(file, testingAlias)
	if len(additional) > 0 {
		support = additional[0]
	}
	for _, p := range s.records {
		parts := []any{s.directives}
		for _, n := range p.contexts {
			parts = append(parts, s.structural(reflect.ValueOf(n)))
		}
		for _, n := range p.rows {
			parts = append(parts, s.structural(reflect.ValueOf(n)))
		}
		dependencies := s.dependencies(appendNodes(p.contexts, exprNodes(p.rows)...), support)
		for _, name := range dependencies {
			decl := support[name]
			parts = append(parts, []any{name, decl.directives, s.structural(reflect.ValueOf(decl.node))})
			for _, imp := range decl.imports {
				parts = append(parts, s.structural(reflect.ValueOf(imp)))
			}
		}
		bytes, _ := json.Marshal(parts)
		sum := sha256.Sum256(bytes)
		p.record.Digest = hex.EncodeToString(sum[:])
		result = append(result, p.record)
	}
	return result, nil
}
func testFunction(fn *ast.FuncDecl, alias string) bool {
	name := fn.Name.Name
	if !strings.HasPrefix(name, "Test") || name == "TestMain" {
		return false
	}
	if len(name) > 4 {
		for _, r := range name[4:] {
			if unicode.IsLower(r) {
				return false
			}
			break
		}
	}
	if fn.Body == nil || fn.Type.Params == nil || len(fn.Type.Params.List) != 1 || fn.Type.Results != nil {
		return false
	}
	p, ok := fn.Type.Params.List[0].Type.(*ast.StarExpr)
	if !ok {
		return false
	}
	sel, ok := p.X.(*ast.SelectorExpr)
	if !ok {
		return false
	}
	x, ok := sel.X.(*ast.Ident)
	return ok && x.Name == alias && sel.Sel.Name == "T"
}
func runCall(n ast.Node, receiver string) *ast.CallExpr {
	c, ok := n.(*ast.CallExpr)
	if !ok {
		return nil
	}
	sel, ok := c.Fun.(*ast.SelectorExpr)
	if !ok || sel.Sel.Name != "Run" {
		return nil
	}
	x, ok := sel.X.(*ast.Ident)
	if !ok || x.Name != receiver {
		return nil
	}
	return c
}
func hasRun(n ast.Node, receiver string) bool {
	found := false
	ast.Inspect(n, func(n ast.Node) bool {
		if n == nil {
			return true
		}
		if runCall(n, receiver) != nil {
			found = true
		}
		return true
	})
	return found
}
func hasRunReference(n ast.Node, receiver string) bool {
	found := false
	ast.Inspect(n, func(n ast.Node) bool {
		if sel, ok := n.(*ast.SelectorExpr); ok && sel.Sel.Name == "Run" {
			if x, ok := sel.X.(*ast.Ident); ok && x.Name == receiver {
				found = true
			}
		}
		return true
	})
	return found
}
func normalizeName(name string) string {
	var b strings.Builder
	for _, r := range name {
		if unicode.IsSpace(r) {
			b.WriteRune('_')
		} else if !strconv.IsPrint(r) {
			b.WriteString(strconv.QuoteRune(r)[1 : len(strconv.QuoteRune(r))-1])
		} else {
			b.WriteRune(r)
		}
	}
	return b.String()
}
func literalName(e ast.Expr) (string, error) {
	l, ok := e.(*ast.BasicLit)
	if !ok || l.Kind != token.STRING {
		return "", fmt.Errorf("test names must be literal strings")
	}
	name, err := strconv.Unquote(l.Value)
	if err != nil {
		return "", err
	}
	if name == "" {
		return "", fmt.Errorf("empty test names are unsupported")
	}
	return normalizeName(name), nil
}
func callback(c *ast.CallExpr) (*ast.FuncLit, string, error) {
	if len(c.Args) != 2 {
		return nil, "", fmt.Errorf("t.Run must have name and literal callback")
	}
	fn, ok := c.Args[1].(*ast.FuncLit)
	if !ok || len(fn.Type.Params.List) != 1 || len(fn.Type.Params.List[0].Names) != 1 {
		return nil, "", fmt.Errorf("t.Run requires a literal callback with a named testing parameter")
	}
	return fn, fn.Type.Params.List[0].Names[0].Name, nil
}
func appendNodes(a []ast.Node, n ...ast.Node) []ast.Node {
	return append(append([]ast.Node{}, a...), n...)
}
func appendRows(a []ast.Expr, n ast.Expr) []ast.Expr { return append(append([]ast.Expr{}, a...), n) }
func (s *sourceScanner) walk(body *ast.BlockStmt, receiver, name, parent, group string, contexts []ast.Node, rows []ast.Expr, location ast.Node, kind string, rowIndex *int) error {
	s.receivers[receiver] = true
	if aliasesReceiver(body, receiver) {
		return fmt.Errorf("%s: testing receiver aliases or escaped assignments are unsupported", s.path)
	}
	id := s.pkg + "::" + name
	if s.names[id] {
		return fmt.Errorf("%s: duplicate or normalized runtime-name collision: %s", s.path, name)
	}
	s.names[id] = true
	idx := len(s.records)
	p := s.fset.Position(location.Pos())
	end := s.fset.Position(location.End())
	parentID := ""
	if parent != "" {
		parentID = s.pkg + "::" + parent
	}
	s.records = append(s.records, pendingRecord{Record{ID: id, FullDescription: name, FilePath: s.path, LineNumber: p.Line, Digest: "", Package: s.pkg, TestName: name, ParentID: parentID, GroupID: s.pkg + "::" + group, Source: SourceLocation{kind, p.Offset, end.Offset, rowIndex}}, contexts, rows})
	locals := map[string]*ast.CompositeLit{}
	for _, stmt := range body.List {
		// A local table is enumerable only while its literal inventory remains private
		// and untouched. References in nested statements, aliases, and calls invalidate it.
		for local := range locals {
			var use ast.Node = stmt
			if rng, ok := stmt.(*ast.RangeStmt); ok {
				if ident, ok := rng.X.(*ast.Ident); ok && ident.Name == local {
					use = rng.Body
				}
			}
			if containsIdentifier(use, local) {
				delete(locals, local)
			}
		}
		switch v := stmt.(type) {
		case *ast.AssignStmt:
			for _, lhs := range v.Lhs {
				if name := assignedRoot(lhs); name != "" {
					delete(locals, name)
				}
			}
			if len(v.Lhs) == 1 && len(v.Rhs) == 1 {
				if ident, ok := v.Lhs[0].(*ast.Ident); ok {
					if table, ok := v.Rhs[0].(*ast.CompositeLit); ok {
						locals[ident.Name] = table
					}
				}
			}
		case *ast.DeclStmt:
			if decl, ok := v.Decl.(*ast.GenDecl); ok {
				for _, spec := range decl.Specs {
					if val, ok := spec.(*ast.ValueSpec); ok && len(val.Names) == 1 && len(val.Values) == 1 {
						if table, ok := val.Values[0].(*ast.CompositeLit); ok {
							locals[val.Names[0].Name] = table
						}
					}
				}
			}
		}
		if expr, ok := stmt.(*ast.ExprStmt); ok {
			if c := runCall(expr.X, receiver); c != nil {
				if len(c.Args) != 2 {
					return fmt.Errorf("%s: t.Run requires two arguments", s.path)
				}
				child, err := literalName(c.Args[0])
				if err != nil {
					return fmt.Errorf("%s:%d: %w", s.path, s.fset.Position(c.Pos()).Line, err)
				}
				fn, arg, err := callback(c)
				if err != nil {
					return err
				}
				s.records[idx].record.IsGroup = true
				if err = s.walk(fn.Body, arg, name+"/"+child, name, group, appendNodes(contexts, fn.Type, fn.Body), rows, stmt, "subtest", nil); err != nil {
					return err
				}
				continue
			}
		}
		if rng, ok := stmt.(*ast.RangeStmt); ok && hasRun(rng.Body, receiver) {
			table, ok := rng.X.(*ast.CompositeLit)
			if !ok {
				if x, yes := rng.X.(*ast.Ident); yes {
					table = locals[x.Name]
				}
			}
			if table == nil {
				return fmt.Errorf("%s: dynamic table source cannot be enumerated", s.path)
			}
			arr, ok := table.Type.(*ast.ArrayType)
			if !ok || arr.Len != nil {
				return fmt.Errorf("%s: table must be a literal struct slice", s.path)
			}
			typ, ok := arr.Elt.(*ast.StructType)
			if !ok {
				return fmt.Errorf("%s: table must be a literal struct slice", s.path)
			}
			iter, ok := rng.Value.(*ast.Ident)
			if !ok || iter.Name == "_" {
				return fmt.Errorf("%s: table range requires a named row value", s.path)
			}
			if changesOrEscapesRow(rng.Body, iter.Name, receiver) {
				return fmt.Errorf("%s: mutated or escaped table rows cannot be enumerated", s.path)
			}
			var call *ast.CallExpr
			for _, st := range rng.Body.List {
				if ex, ok := st.(*ast.ExprStmt); ok {
					if c := runCall(ex.X, receiver); c != nil {
						if call != nil {
							return fmt.Errorf("%s: one direct t.Run required per table range", s.path)
						}
						call = c
						continue
					}
				}
				if hasRun(st, receiver) {
					return fmt.Errorf("%s: conditional/dynamic table registration unsupported", s.path)
				}
			}
			if call == nil || len(call.Args) != 2 {
				return fmt.Errorf("%s: one direct t.Run required per table range", s.path)
			}
			sel, ok := call.Args[0].(*ast.SelectorExpr)
			if !ok {
				return fmt.Errorf("%s: table must register tc.name", s.path)
			}
			x, ok := sel.X.(*ast.Ident)
			if !ok || x.Name != iter.Name {
				return fmt.Errorf("%s: table name must use its range value", s.path)
			}
			field := -1
			pos := 0
			for _, f := range typ.Fields.List {
				for _, n := range f.Names {
					if n.Name == sel.Sel.Name {
						field = pos
					}
					pos++
				}
			}
			if field < 0 {
				return fmt.Errorf("%s: table name field not found", s.path)
			}
			fn, arg, err := callback(call)
			if err != nil {
				return err
			}
			if len(table.Elts) == 0 {
				return fmt.Errorf("%s: empty subtest table is unsupported", s.path)
			}
			s.tables[table] = true
			for i, element := range table.Elts {
				row, ok := element.(*ast.CompositeLit)
				if !ok {
					return fmt.Errorf("%s: table rows must be literal structs", s.path)
				}
				var nameExpr ast.Expr
				for j, e := range row.Elts {
					if kv, ok := e.(*ast.KeyValueExpr); ok {
						key, ok := kv.Key.(*ast.Ident)
						if ok && key.Name == sel.Sel.Name {
							nameExpr = kv.Value
						}
					} else if j == field {
						nameExpr = e
					}
				}
				child, err := literalName(nameExpr)
				if err != nil {
					return fmt.Errorf("%s: table row %d: %w", s.path, i, err)
				}
				ri := i
				s.records[idx].record.IsGroup = true
				if err = s.walk(fn.Body, arg, name+"/"+child, name, group, appendNodes(contexts, rng.Body, fn.Type, fn.Body), appendRows(rows, row), row, "table-row", &ri); err != nil {
					return err
				}
			}
			continue
		}
		if hasRunReference(stmt, receiver) {
			return fmt.Errorf("%s:%d: dynamic or indirect subtest registration unsupported", s.path, s.fset.Position(stmt.Pos()).Line)
		}
	}
	return nil
}

func containsIdentifier(node ast.Node, name string) bool {
	found := false
	ast.Inspect(node, func(node ast.Node) bool {
		if ident, ok := node.(*ast.Ident); ok && ident.Name == name {
			found = true
		}
		return !found
	})
	return found
}

// Selector reads do not copy the receiver/row itself. Other value uses can alias
// it or pass it to code whose registrations/mutations cannot be proved statically.
func containsValueReference(node ast.Node, name string) bool {
	found := false
	ast.Inspect(node, func(node ast.Node) bool {
		if selector, ok := node.(*ast.SelectorExpr); ok {
			if ident, ok := selector.X.(*ast.Ident); ok && ident.Name == name {
				return false
			}
		}
		if ident, ok := node.(*ast.Ident); ok && ident.Name == name {
			found = true
		}
		return !found
	})
	return found
}

func aliasesReceiver(body *ast.BlockStmt, receiver string) bool {
	found := false
	ast.Inspect(body, func(node ast.Node) bool {
		var values []ast.Expr
		switch value := node.(type) {
		case *ast.AssignStmt:
			values = value.Rhs
		case *ast.ValueSpec:
			values = value.Values
		}
		for _, value := range values {
			if assignedReceiverReference(value, receiver) {
				found = true
			}
		}
		return !found
	})
	return found
}

func changesOrEscapesRow(body *ast.BlockStmt, row, receiver string) bool {
	callbacks := map[ast.Node]bool{}
	for _, stmt := range body.List {
		if expr, ok := stmt.(*ast.ExprStmt); ok {
			if call := runCall(expr.X, receiver); call != nil && len(call.Args) == 2 {
				if callback, ok := call.Args[1].(*ast.FuncLit); ok {
					// The runtime name is evaluated before this callback executes.
					callbacks[callback] = true
				}
			}
		}
	}
	found := false
	ast.Inspect(body, func(node ast.Node) bool {
		if callbacks[node] {
			return false
		}
		switch value := node.(type) {
		case *ast.AssignStmt:
			for _, lhs := range value.Lhs {
				if assignedRoot(lhs) == row {
					found = true
				}
			}
		case *ast.IncDecStmt:
			found = found || assignedRoot(value.X) == row
		case *ast.UnaryExpr:
			found = found || value.Op == token.AND && assignedRoot(value.X) == row
		case *ast.SelectorExpr:
			if ident, ok := value.X.(*ast.Ident); ok && ident.Name == row {
				return false
			}
		case *ast.Ident:
			found = found || value.Name == row
		}
		return !found
	})
	return found
}

func assignedRoot(expr ast.Expr) string {
	switch value := expr.(type) {
	case *ast.Ident:
		return value.Name
	case *ast.IndexExpr:
		return assignedRoot(value.X)
	case *ast.SelectorExpr:
		return assignedRoot(value.X)
	case *ast.StarExpr:
		return assignedRoot(value.X)
	case *ast.ParenExpr:
		return assignedRoot(value.X)
	}
	return ""
}

// Encode AST structure without positions, comments or parser object cycles. Omit
// registrations from shared contexts and table row inventories from shared setup.
func (s *sourceScanner) structural(v reflect.Value) any {
	if !v.IsValid() {
		return nil
	}
	if v.Kind() == reflect.Interface {
		if v.IsNil() {
			return nil
		}
		return s.structural(v.Elem())
	}
	if v.Kind() == reflect.Pointer {
		if v.IsNil() {
			return nil
		}
		if n, ok := v.Interface().(ast.Node); ok {
			if s.tables[n] {
				if t, ok := n.(*ast.CompositeLit); ok {
					return []any{"table", s.structural(reflect.ValueOf(t.Type))}
				}
			}
			if block, ok := n.(*ast.BlockStmt); ok {
				out := []any{"block"}
				for _, stmt := range block.List {
					if s.registration(stmt) {
						continue
					}
					out = append(out, s.structural(reflect.ValueOf(stmt)))
				}
				return out
			}
		}
		return s.structural(v.Elem())
	}
	if v.Type() == reflect.TypeOf(token.Pos(0)) {
		return nil
	}
	switch v.Kind() {
	case reflect.Struct:
		out := []any{v.Type().String()}
		for i := 0; i < v.NumField(); i++ {
			f := v.Type().Field(i)
			if f.Name == "Obj" || f.Name == "Scope" || f.Name == "Doc" || f.Name == "Comment" || f.Name == "Comments" || f.Type == reflect.TypeOf(token.Pos(0)) {
				continue
			}
			out = append(out, []any{f.Name, s.structural(v.Field(i))})
		}
		return out
	case reflect.Slice:
		out := []any{}
		for i := 0; i < v.Len(); i++ {
			out = append(out, s.structural(v.Index(i)))
		}
		return out
	case reflect.String:
		return v.String()
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return v.Int()
	case reflect.Bool:
		return v.Bool()
	}
	return nil
}
func sortRecords(records []Record) {
	sort.Slice(records, func(i, j int) bool { return records[i].ID < records[j].ID })
}

// A helper call may accept testing.T and return an ordinary fixture value.
// Its arguments are not receiver copies. Direct copies, closures capturing the
// receiver, and Run method values remain unsupported registration escape paths.
func assignedReceiverReference(expr ast.Expr, receiver string) bool {
	found := false
	ast.Inspect(expr, func(node ast.Node) bool {
		if call, ok := node.(*ast.CallExpr); ok {
			found = found || hasRunReference(call, receiver)
			return false
		}
		if selector, ok := node.(*ast.SelectorExpr); ok {
			if ident, ok := selector.X.(*ast.Ident); ok && ident.Name == receiver {
				found = found || selector.Sel.Name == "Run"
				return false
			}
		}
		if ident, ok := node.(*ast.Ident); ok && ident.Name == receiver {
			found = true
		}
		return !found
	})
	return found
}
