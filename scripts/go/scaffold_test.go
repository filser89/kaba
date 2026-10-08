package main

import (
	"go/types"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func scaffoldFixture(t *testing.T, production, support string) (string, string, string, listedPackage) {
	t.Helper()
	root := t.TempDir()
	feature := filepath.Join(root, "features", "one")
	dir := filepath.Join(root, "testdata", "kaba", "one")
	for _, d := range []string{feature, dir} {
		if err := os.MkdirAll(d, 0700); err != nil {
			t.Fatal(err)
		}
	}
	for name, content := range map[string]string{"pay.go": production, "testdata/kaba/one/api.go": support} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
	return root, feature, t.TempDir(), listedPackage{ImportPath: "example/demo", Dir: root, GoFiles: []string{"pay.go"}}
}

func TestScaffoldAcceptedMinimalForms(t *testing.T) {
	for _, declaration := range []string{
		`type New struct { Value int }; func Make() New { var z New; return z }`,
		`func Void() {}`, `func Zero() int { return 0 }`, `func Nil() *Old { return nil }`,
		`func Empty() string { return "" }`, `func False() bool { return false }`,
		`func Named() (z int) { return }`, `func (o *Old) Missing() int { return 0 }`,
		`type Old struct { Added string }`,
	} {
		t.Run(declaration, func(t *testing.T) {
			root, feature, out, pkg := scaffoldFixture(t, `package demo; type Old struct { Original int }; func OldBehavior() int { return 42 }`, "package demo; "+declaration)
			before, _ := os.ReadFile(filepath.Join(root, "pay.go"))
			result, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil })
			if err != nil {
				t.Fatal(err)
			}
			if result.Overlay == nil || len(result.Files) != 1 || len(result.Packages) != 1 {
				t.Fatalf("metadata: %+v", result)
			}
			after, _ := os.ReadFile(filepath.Join(root, "pay.go"))
			if string(before) != string(after) {
				t.Fatal("production changed")
			}
		})
	}
}

func TestScaffoldRejectsBusinessBodiesAndDuplicates(t *testing.T) {
	for _, declaration := range []string{
		`func New() int { return 1 }`, `func New() { panic("red") }`, `func init() {}`, `var State = 0`, `const State=0`,
		`func New() int { var z int; z++; return z }`, `func New() int { if true { return 0 }; return 0 }`,
		`func OldBehavior() int { return 0 }`, `type Old struct { Original string }`,
		`type Old int`, `func (o Old) Existing() {}`, `func New() {}; func New(){}`,
		`import _ "net/http"; type New struct{}`,
		`func New(false bool) bool { return false }`,
		`func New(nil int) int { return nil }`,
		`type Old struct { Existing int }`,
		`func (o Old) Original() int { return 0 }`,
		`type New struct { Same int; Same string }`,
		`type Old struct { Added int }; func (Old) Added() int { return 0 }`,
		`func (Old) Added() int { return 0 }; type Old struct { Added int }`,
	} {
		root, feature, out, pkg := scaffoldFixture(t, `package demo; type Old struct { Original int }; func OldBehavior() int { return 42 }; func(Old) Existing(){}`, "package demo; "+declaration)
		if _, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil }); err == nil {
			t.Errorf("accepted %s", declaration)
		}
	}
}

func TestScaffoldAdditiveFieldsPreserveBehavior(t *testing.T) {
	root, feature, out, pkg := scaffoldFixture(t, `package demo; type Old struct { Original int }; func OldBehavior() int { return 42 }`, `package demo; import "time"; type Old struct { Added time.Time }; func New() int { return 0 }`)
	result, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil })
	if err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(*result.Overlay)
	if !strings.Contains(string(data), "pay.go") {
		t.Fatal("missing transformed source")
	}
	files, _ := filepath.Glob(filepath.Join(out, "*.go"))
	found := false
	for _, f := range files {
		b, _ := os.ReadFile(f)
		if strings.Contains(string(b), "OldBehavior") {
			found = true
			if !strings.Contains(string(b), "return 42") || !strings.Contains(string(b), "Added time.Time") {
				t.Fatalf("transformation lost behavior: %s", b)
			}
		}
	}
	if !found {
		t.Fatal("no additive source")
	}
}

func TestScaffoldRejectsOwnershipSymlinksAndStaleOutputs(t *testing.T) {
	root, feature, out, pkg := scaffoldFixture(t, `package demo`, `package demo; func New(){}`)
	if _, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return os.ErrPermission }); err == nil {
		t.Fatal("unowned scaffold accepted")
	}
	if err := os.WriteFile(filepath.Join(out, "stale.go"), []byte("stale"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil }); err == nil {
		t.Fatal("stale output accepted")
	}
	if _, err := buildScaffold(root, feature, root, []listedPackage{pkg}, func(string) error { return nil }); err == nil {
		t.Fatal("production output accepted")
	}
	outside := filepath.Join(t.TempDir(), "api.go")
	if err := os.WriteFile(outside, []byte("package demo; func New(){}"), 0600); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "testdata", "kaba", "one", "api.go")
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, path); err != nil {
		t.Fatal(err)
	}
	if _, err := buildScaffold(root, feature, t.TempDir(), []listedPackage{pkg}, func(string) error { return nil }); err == nil {
		t.Fatal("outside source symlink accepted")
	}
}

func TestScaffoldRejectsShadowedPackageZero(t *testing.T) {
	root, feature, out, pkg := scaffoldFixture(t, `package demo; var false = true`, `package demo; func New() bool { return false }`)
	if _, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil }); err == nil {
		t.Fatal("package shadowed false supplied behavior")
	}
}

func TestScaffoldNoSupportProducesNoOverlay(t *testing.T) {
	root, feature, out, pkg := scaffoldFixture(t, `package demo`, `package demo;func New(){}`)
	if err := os.Remove(filepath.Join(root, "testdata", "kaba", "one", "api.go")); err != nil {
		t.Fatal(err)
	}
	result, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil })
	if err != nil {
		t.Fatal(err)
	}
	if result.Overlay != nil || len(result.Files) != 0 || len(result.Packages) != 0 {
		t.Fatalf("unexpected overlay: %+v", result)
	}
}

func TestScaffoldRejectsVirtualFileCollision(t *testing.T) {
	root, feature, out, pkg := scaffoldFixture(t, `package demo`, `package demo;func New(){}`)
	path := filepath.Join(root, "zz_kaba_scaffold_000.go")
	if err := os.WriteFile(path, []byte("package demo"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil }); err == nil {
		t.Fatal("real virtual-path collision accepted")
	}
}

func TestScaffoldExistingOrdinaryStructFields(t *testing.T) {
	for _, support := range []string{"", "package demo; func Missing() int { return 0 }", "package demo; type Old struct { Added int }"} {
		t.Run(support, func(t *testing.T) {
			root, feature, out, pkg := scaffoldFixture(t, `package demo; type Embedded[T any] struct { Value T }; type Old struct { _ [8]byte; Embedded[int] }; func ExistingBehavior() int { return 42 }`, support)
			if support == "" {
				if err := os.Remove(filepath.Join(root, "testdata/kaba/one/api.go")); err != nil {
					t.Fatal(err)
				}
			}
			result, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil })
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(root, "go.mod"), []byte("module example/demo\n\ngo 1.23\n"), 0600); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(root, "pay_test.go"), []byte(`package demo; import "testing"; func TestExisting(t *testing.T) { if ExistingBehavior()!=42 { t.Fatal("existing behavior changed") } }`), 0600); err != nil {
				t.Fatal(err)
			}
			args := []string{"test", "-count=1"}
			if result.Overlay != nil {
				args = append(args, "-overlay", *result.Overlay)
			}
			cmd := exec.Command("go", args...)
			cmd.Dir = root
			if output, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("real Go execution: %s: %v", output, err)
			}
		})
	}
}

func TestScaffoldRejectsPredeclaredPackageNames(t *testing.T) {
	for _, name := range types.Universe.Names() {
		for _, declaration := range []string{"func " + name + "(x []int) int { return 0 }", "type " + name + " struct{}"} {
			t.Run(declaration, func(t *testing.T) {
				root, feature, out, pkg := scaffoldFixture(t, `package demo; func ExistingBehavior() int { return len([]int{1,2,3}) }`, "package demo; "+declaration)
				if _, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil }); err == nil {
					t.Fatalf("accepted scope-changing declaration %s", declaration)
				}
			})
		}
	}
}

func TestScaffoldPredeclaredMethodNameIsNotPackageBinding(t *testing.T) {
	root, feature, out, pkg := scaffoldFixture(t, `package demo;type Old struct{}`, `package demo;func(Old) len() int{return 0}`)
	if _, err := buildScaffold(root, feature, out, []listedPackage{pkg}, func(string) error { return nil }); err != nil {
		t.Fatal(err)
	}
}
