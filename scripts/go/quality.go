package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"regexp"
	"strconv"
	"strings"
)

var safeRemovalFeature = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)

func stringLiteral(expr ast.Expr) (string, bool) {
	lit, ok := expr.(*ast.BasicLit)
	if !ok || lit.Kind != token.STRING {
		return "", false
	}
	text, err := strconv.Unquote(lit.Value)
	return text, err == nil
}

// goRemovalMarker returns either a literal feature or the table variable whose
// removedBy field supplies the feature. It never infers runtime pending status.
func goRemovalMarker(call *ast.CallExpr) (feature, tableVariable string, marked bool, err error) {
	sel, ok := call.Fun.(*ast.SelectorExpr)
	if !ok || (sel.Sel.Name != "Skip" && sel.Sel.Name != "Skipf" && sel.Sel.Name != "SkipNow") {
		return
	}
	for _, arg := range call.Args {
		ast.Inspect(arg, func(n ast.Node) bool {
			if expr, ok := n.(ast.Expr); ok {
				if text, literal := stringLiteral(expr); literal && strings.Contains(text, "REMOVED") {
					marked = true
				}
			}
			return true
		})
	}
	if !marked {
		return
	}
	err = fmt.Errorf("unsupported REMOVED marker; use t.Skip(\"REMOVED by <feature>\") or guarded removedBy table convention")
	if sel.Sel.Name != "Skip" || len(call.Args) != 1 {
		return
	}
	if text, literal := stringLiteral(call.Args[0]); literal && strings.HasPrefix(text, "REMOVED by ") {
		feature = strings.TrimPrefix(text, "REMOVED by ")
		if safeRemovalFeature.MatchString(feature) {
			err = nil
		}
		return
	}
	bin, ok := call.Args[0].(*ast.BinaryExpr)
	if !ok || bin.Op != token.ADD {
		return
	}
	text, literal := stringLiteral(bin.X)
	field, ok := bin.Y.(*ast.SelectorExpr)
	if !literal || text != "REMOVED by " || !ok || field.Sel.Name != "removedBy" {
		return
	}
	variable, ok := field.X.(*ast.Ident)
	if !ok {
		return
	}
	tableVariable, err = variable.Name, nil
	return
}

func removalGuard(stmt *ast.IfStmt, call *ast.CallExpr, variable string) bool {
	if call.Pos() < stmt.Body.Pos() || call.End() > stmt.Body.End() {
		return false
	}
	condition, ok := stmt.Cond.(*ast.BinaryExpr)
	if !ok || condition.Op != token.NEQ {
		return false
	}
	field, ok := condition.X.(*ast.SelectorExpr)
	empty, literal := stringLiteral(condition.Y)
	if !ok || !literal || empty != "" {
		field, ok = condition.Y.(*ast.SelectorExpr)
		empty, literal = stringLiteral(condition.X)
	}
	if !ok || !literal || empty != "" || field.Sel.Name != "removedBy" {
		return false
	}
	ident, ok := field.X.(*ast.Ident)
	return ok && ident.Name == variable
}

// validateGoRemovalMarkers is shared by quality and cleanup. Cleanup must also
// resolve exact source records, literal row features, and pending runtime results.
func validateGoRemovalMarkers(file *ast.File) error {
	var problem error
	stack := []ast.Node{}
	ast.Inspect(file, func(n ast.Node) bool {
		if n == nil {
			stack = stack[:len(stack)-1]
			return false
		}
		if problem != nil {
			return false
		}
		stack = append(stack, n)
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}
		_, variable, marked, err := goRemovalMarker(call)
		if err != nil {
			problem = err
			return true
		}
		if !marked || variable == "" {
			return true
		}
		guarded, callback := false, false
		// The table guard must be in the same literal callback as its skip.
		for i := len(stack) - 2; i >= 0; i-- {
			if stmt, ok := stack[i].(*ast.IfStmt); ok && removalGuard(stmt, call, variable) {
				guarded = true
			}
			if _, ok := stack[i].(*ast.FuncLit); ok {
				callback = true
				break
			}
			if _, ok := stack[i].(*ast.FuncDecl); ok {
				break
			}
		}
		if !guarded || !callback {
			problem = fmt.Errorf("table REMOVED marker requires if %s.removedBy != \"\" in its callback", variable)
		}
		return true
	})
	return problem
}

// Inventory owns registration-shape validation; the project owns assertion style.
func qualityCommand(files []string) error {
	if len(files) == 0 {
		return fmt.Errorf("quality requires discovered Go test files")
	}
	for _, path := range files {
		file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
		if err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		if err := validateGoRemovalMarkers(file); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
	}
	return nil
}
