package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type goEdit struct {
	Start int `json:"start"`
	End   int `json:"end"`
}
type goCleanupFile struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}
type goCleanupPlan struct {
	Files   []goCleanupFile `json:"files"`
	Removed []string        `json:"removed"`
}

func applyGoEdits(src []byte, edits []goEdit) ([]byte, error) {
	sort.Slice(edits, func(i, j int) bool { return edits[i].Start > edits[j].Start })
	out := append([]byte(nil), src...)
	last := len(src)
	for _, e := range edits {
		if e.Start < 0 || e.End > last || e.Start >= e.End {
			return nil, fmt.Errorf("overlapping or invalid deletion")
		}
		out = append(out[:e.Start], out[e.End:]...)
		last = e.Start
	}
	return out, nil
}
func planGoRemovals(src []byte, records []Record, status map[string]string, feature string) ([]goEdit, []string, error) {
	fs := token.NewFileSet()
	file, err := parser.ParseFile(fs, "cleanup.go", src, parser.ParseComments)
	if err != nil {
		return nil, nil, err
	}
	if err = validateGoRemovalMarkers(file); err != nil {
		return nil, nil, err
	}
	offset := func(n ast.Node) (int, int) { return fs.Position(n.Pos()).Offset, fs.Position(n.End()).Offset }
	edits := []goEdit{}
	ids := []string{}
	for _, rec := range records {
		if rec.IsGroup {
			continue
		}
		var unit ast.Node
		var row *ast.CompositeLit
		var table *ast.CompositeLit
		var fn *ast.FuncDecl
		for _, decl := range file.Decls {
			f, ok := decl.(*ast.FuncDecl)
			if !ok {
				continue
			}
			start, end := offset(f)
			if rec.Source.StartOffset >= start && rec.Source.EndOffset <= end {
				fn = f
				break
			}
		}
		ast.Inspect(file, func(n ast.Node) bool {
			if n == nil {
				return false
			}
			a, b := offset(n)
			if a == rec.Source.StartOffset && b == rec.Source.EndOffset {
				unit = n
				if r, ok := n.(*ast.CompositeLit); ok {
					row = r
				}
			}
			return true
		})
		if unit == nil || fn == nil {
			return nil, nil, fmt.Errorf("unresolved source for %s", rec.ID)
		}
		matched := false
		if rec.Source.Kind == "table-row" {
			ast.Inspect(fn, func(n ast.Node) bool {
				lit, ok := n.(*ast.CompositeLit)
				if !ok {
					return true
				}
				for _, el := range lit.Elts {
					if el == row {
						table = lit
					}
				}
				return true
			})
			if table == nil {
				return nil, nil, fmt.Errorf("unresolved table for %s", rec.ID)
			}
			removedBy := ""
			found := false
			fieldSeen := false
			keyed := false
			for _, el := range row.Elts {
				if kv, ok := el.(*ast.KeyValueExpr); ok {
					keyed = true
					if key, ok := kv.Key.(*ast.Ident); ok && key.Name == "removedBy" {
						fieldSeen = true
						removedBy, found = stringLiteral(kv.Value)
					}
				}
			}
			if !found && !keyed {
				if arr, ok := table.Type.(*ast.ArrayType); ok {
					if st, ok := arr.Elt.(*ast.StructType); ok {
						index := 0
						for _, field := range st.Fields.List {
							for _, name := range field.Names {
								if name.Name == "removedBy" && index < len(row.Elts) {
									fieldSeen = true
									removedBy, found = stringLiteral(row.Elts[index])
								}
								index++
							}
						}
					}
				}
			}
			if fieldSeen && !found {
				return nil, nil, fmt.Errorf("dynamic removedBy field is not removable")
			}
			if !found || removedBy == "" {
				continue
			}
			if !safeRemovalFeature.MatchString(removedBy) {
				return nil, nil, fmt.Errorf("invalid removedBy field")
			}
			if removedBy != feature {
				continue
			}
			// Bind the marker to this exact table's range callback.
			tableName := ""
			ast.Inspect(fn.Body, func(n ast.Node) bool {
				switch n := n.(type) {
				case *ast.AssignStmt:
					for i, rhs := range n.Rhs {
						if rhs == table && i < len(n.Lhs) {
							if id, ok := n.Lhs[i].(*ast.Ident); ok {
								tableName = id.Name
							}
						}
					}
				case *ast.ValueSpec:
					for i, value := range n.Values {
						if value == table && i < len(n.Names) {
							tableName = n.Names[i].Name
						}
					}
				}
				return true
			})
			dynamic := 0
			ast.Inspect(fn.Body, func(n ast.Node) bool {
				rangeStmt, ok := n.(*ast.RangeStmt)
				if !ok {
					return true
				}
				bound := rangeStmt.X == table
				if name, ok := rangeStmt.X.(*ast.Ident); ok && tableName != "" && name.Name == tableName {
					bound = true
				}
				if !bound {
					return true
				}
				value, ok := rangeStmt.Value.(*ast.Ident)
				if !ok {
					return true
				}
				for _, stmt := range rangeStmt.Body.List {
					expr, ok := stmt.(*ast.ExprStmt)
					if !ok {
						continue
					}
					run, ok := expr.X.(*ast.CallExpr)
					if !ok {
						continue
					}
					sel, ok := run.Fun.(*ast.SelectorExpr)
					if !ok || sel.Sel.Name != "Run" || len(run.Args) != 2 {
						continue
					}
					callback, ok := run.Args[1].(*ast.FuncLit)
					if !ok {
						continue
					}
					ast.Inspect(callback.Body, func(n ast.Node) bool {
						if _, nested := n.(*ast.FuncLit); nested {
							return false
						}
						if call, ok := n.(*ast.CallExpr); ok {
							_, v, m, e := goRemovalMarker(call)
							if e == nil && m && v == value.Name {
								dynamic++
							}
						}
						return true
					})
				}
				return true
			})
			if dynamic != 1 {
				return nil, nil, fmt.Errorf("ambiguous table removal callback for %s", rec.ID)
			}

			matched = true
		} else if rec.Source.Kind == "function" || rec.Source.Kind == "subtest" {
			ast.Inspect(unit, func(n ast.Node) bool {
				if call, ok := n.(*ast.CallExpr); ok {
					f, v, m, e := goRemovalMarker(call)
					if e == nil && m && v == "" && f == feature {
						matched = true
					}
				}
				return true
			})
		} else {
			continue
		}
		if !matched {
			continue
		}
		if status[rec.ID] != "pending" {
			return nil, nil, fmt.Errorf("marked case %s must report skipped/pending", rec.ID)
		}
		start, end := rec.Source.StartOffset, rec.Source.EndOffset
		if row != nil {
			if len(table.Elts) <= 1 {
				return nil, nil, fmt.Errorf("last table row removal exposes parent identity")
			}
			after := end
			for after < len(src) && (src[after] == ' ' || src[after] == '\t' || src[after] == '\n' || src[after] == '\r') {
				after++
			}
			if after < len(src) && src[after] == ',' {
				end = after + 1
			} else {
				before := start - 1
				for before >= 0 && (src[before] == ' ' || src[before] == '\t' || src[before] == '\n' || src[before] == '\r') {
					before--
				}
				if before < 0 || src[before] != ',' {
					return nil, nil, fmt.Errorf("row separator unresolved")
				}
				start = before
			}
		}
		edits = append(edits, goEdit{start, end})
		ids = append(ids, rec.ID)
	}
	out, err := applyGoEdits(src, edits)
	if err != nil {
		return nil, nil, err
	}
	if len(edits) > 0 {
		// Refuse any source change that creates identities, including final-row parents.
		next, err := scanSource(records[0].Package, records[0].FilePath, out)
		if err != nil {
			return nil, nil, err
		}
		expected := map[string]bool{}
		for _, r := range records {
			if !r.IsGroup {
				expected[r.ID] = true
			}
		}
		for _, id := range ids {
			delete(expected, id)
		}
		for _, r := range next {
			if r.IsGroup {
				continue
			}
			if !expected[r.ID] {
				return nil, nil, fmt.Errorf("unexpected remaining identity %s", r.ID)
			}
			delete(expected, r.ID)
		}
		if len(expected) != 0 {
			return nil, nil, fmt.Errorf("remaining identities differ")
		}
	}
	return edits, ids, nil
}
func cleanupCommand(args []string) error {
	flags := flag.NewFlagSet("cleanup", flag.ContinueOnError)
	root := flags.String("root", "", "repository root")
	feature := flags.String("feature", "", "feature basename")
	results := flags.String("results", "", "complete real runner results")
	output := flags.String("output", "", "plan path")
	goBin := flags.String("go-bin", "go", "Go executable for import resolution")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *root == "" || *feature == "" || *results == "" || *output == "" || flags.NArg() != 0 {
		return fmt.Errorf("cleanup requires --root --feature --results --output")
	}
	data, err := os.ReadFile(*results)
	if err != nil {
		return err
	}
	var run struct {
		Examples []struct {
			Record
			Status string `json:"status"`
		} `json:"examples"`
		Groups  []Record `json:"groups"`
		Context struct {
			Tags string `json:"tags"`
		} `json:"context"`
	}
	if err = json.Unmarshal(data, &run); err != nil {
		return err
	}
	files := map[string][]Record{}
	statuses := map[string]string{}
	for _, ex := range run.Examples {
		files[ex.FilePath] = append(files[ex.FilePath], ex.Record)
		statuses[ex.ID] = ex.Status
	}
	for _, g := range run.Groups {
		files[g.FilePath] = append(files[g.FilePath], g)
	}
	absoluteRoot, err := filepath.Abs(*root)
	if err != nil {
		return err
	}
	imports := cleanupImportResolver{root: absoluteRoot, goBin: *goBin, tags: run.Context.Tags}
	plan := goCleanupPlan{Files: []goCleanupFile{}, Removed: []string{}}
	for path, recs := range files {
		if filepath.IsAbs(path) || (filepath.Clean(path) != path || path == ".." || strings.HasPrefix(path, "../")) || strings.ContainsAny(path, "\r\n\t") {
			return fmt.Errorf("unsafe source path")
		}
		src, err := os.ReadFile(filepath.Join(*root, path))
		if err != nil {
			return err
		}
		edits, ids, err := planGoRemovals(src, recs, statuses, *feature)
		if err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		if len(edits) > 0 {
			importEdits, err := imports.removals(path, src, edits)
			if err != nil {
				return fmt.Errorf("%s: %w", path, err)
			}
			edits = append(edits, importEdits...)
			changed, err := applyGoEdits(src, edits)
			if err != nil {
				return err
			}
			if bytes.Equal(src, changed) {
				return fmt.Errorf("empty edit")
			}
			plan.Files = append(plan.Files, goCleanupFile{path, string(changed)})
			plan.Removed = append(plan.Removed, ids...)
		}
	}
	sort.Slice(plan.Files, func(i, j int) bool { return plan.Files[i].Path < plan.Files[j].Path })
	sort.Strings(plan.Removed)
	data, err = json.Marshal(plan)
	if err != nil {
		return err
	}
	return os.WriteFile(*output, data, 0600)
}
