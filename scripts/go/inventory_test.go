package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func source(body string) string {
	return "package demo\nimport \"testing\"\nfunc TestPay(t *testing.T) {\n" + body + "\n}\n"
}

func TestAllPackageInitializersAffectDigests(t *testing.T) {
	base := source(`if expected != 1 { t.Fatal(expected) }`) + `
var expected int
func initialize() int { return 1 }
func init() { expected = initialize() }
func init() { expected++ }
`
	a := leaves(discover(t, base))["TestPay"]
	for _, changed := range []string{
		strings.Replace(base, "return 1", "return 2", 1),
		strings.Replace(base, "expected++", "expected += 2", 1),
	} {
		if a.Digest == leaves(discover(t, changed))["TestPay"].Digest {
			t.Fatal("package initializer or its helper omitted")
		}
	}
}

func TestConstantDeclarationSemanticsAffectDigests(t *testing.T) {
	for _, declarations := range [][2]string{
		{`const (A=1; B)`, `const (A=2; B)`},
		{`const (A=iota; B)`, `const (X=iota; A; B)`},
		{`const B=1`, `var B=1`},
	} {
		a := leaves(discover(t, source(`if B != 1 { t.Fatal(B) }`)+declarations[0]))["TestPay"]
		b := leaves(discover(t, source(`if B != 1 { t.Fatal(B) }`)+declarations[1]))["TestPay"]
		if a.Digest == b.Digest {
			t.Errorf("declaration semantics omitted: %s / %s", declarations[0], declarations[1])
		}
	}
}

func TestAllMethodCandidatesAffectDigests(t *testing.T) {
	base := source(`if (first{}).Check() != 1 { t.Fatal("first") }`) + `
type first struct{}
type second struct{}
func (first) Check() int { return 1 }
func (second) Check() int { return 1 }
`
	a := leaves(discover(t, base))["TestPay"]
	b := leaves(discover(t, strings.Replace(base, "return 1", "return 2", 1)))["TestPay"]
	if a.Digest == b.Digest {
		t.Fatal("first method overwritten by later method")
	}
}

func TestPackageSupportKeepsMultipleInitializersAndMethods(t *testing.T) {
	dir := t.TempDir()
	files := []string{"a_test.go", "b_test.go"}
	write := func(name, content string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
	}
	write(files[0], source(`if (first{}).Check() != 1 { t.Fatal("first") }`)+`type first struct{};func(first) Check() int{return 1};func init(){println("first")}`)
	write(files[1], `package demo;type second struct{};func(second) Check() int{return 1};func init(){println("second")}`)
	a, err := scanPackage("pkg", dir, ".", files)
	if err != nil {
		t.Fatal(err)
	}
	write(files[1], `package demo;type second struct{};func(second) Check() int{return 2};func init(){println("changed")}`)
	b, err := scanPackage("pkg", dir, ".", files)
	if err != nil {
		t.Fatal(err)
	}
	if a[0].Digest == b[0].Digest {
		t.Fatal("cross-file support candidates omitted")
	}
}

func TestRejectReceiverAliasesAndTableEscapes(t *testing.T) {
	for _, body := range []string{
		`alias:=t;alias.Run("hidden",func(t *testing.T){})`,
		`var alias = t;alias.Run("hidden",func(t *testing.T){})`,
		`if true {alias:=t;alias.Run("hidden",func(t *testing.T){})}`,
		`cases:=[]struct{name string}{{"one"}};if true{cases[0].name="two"};for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){})}`,
		`cases:=[]struct{name string}{{"one"}};mutate(cases);for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){})}`,
		`cases:=[]struct{name string}{{"one"}};alias:=cases;alias[0].name="two";for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){})}`,
		`for _,tc:=range []struct{name string}{{"one"}}{tc.name="two";t.Run(tc.name,func(t *testing.T){})}`,
		`for _,tc:=range []struct{name string}{{"one"}}{mutate(&tc);t.Run(tc.name,func(t *testing.T){})}`,
	} {
		if _, err := scanSource("pkg", "x_test.go", []byte(source(body))); err == nil {
			t.Errorf("accepted unprovable inventory: %s", body)
		}
	}
}
func TestRejectRowFieldPointerEscapesBeforeRegistration(t *testing.T) {
	for _, setup := range []string{
		`rename(&tc.name)`,
		`rename(&(tc.name))`,
		`name := &tc.name; *name = "two"`,
		`if true { rename(&tc.name) }`,
	} {
		body := `for _,tc:=range []struct{name string}{{"one"}}{` + setup + `;t.Run(tc.name,func(t *testing.T){})}`
		if _, err := scanSource("pkg", "x_test.go", []byte(source(body))); err == nil || !strings.Contains(err.Error(), "mutated or escaped table rows") {
			t.Errorf("field pointer escape requires an explicit inventory error: %s; error: %v", setup, err)
		}
	}
}
func TestRowFieldPointersInsideRegisteredCallback(t *testing.T) {
	for _, callback := range []string{
		`assertName(t, &tc.name)`,
		`name := &tc.name; assertName(t, name)`,
	} {
		body := `for _,tc:=range []struct{name string}{{"one"}}{t.Run(tc.name,func(t *testing.T){` + callback + `})}`
		cases := leaves(discover(t, source(body)))
		if len(cases) != 1 || cases["TestPay/one"].TestName != "TestPay/one" {
			t.Fatalf("callback field pointer altered the registered inventory: %+v", cases)
		}
	}
}
func discover(t *testing.T, s string) []Record {
	t.Helper()
	r, e := scanSource("example/demo", "pay_test.go", []byte(s))
	if e != nil {
		t.Fatal(e)
	}
	return r
}
func leaves(r []Record) map[string]Record {
	m := map[string]Record{}
	for _, v := range r {
		if !v.IsGroup {
			m[v.TestName] = v
		}
	}
	return m
}
func TestLiteralAndNestedInventory(t *testing.T) {
	r := discover(t, source(`t.Fatal("setup")
 t.Run("one",func(t *testing.T){ t.Run("nested",func(t *testing.T){t.Error("red")}) })
 t.Run("two",func(t *testing.T){t.Parallel()})`))
	if len(r) != 4 || len(leaves(r)) != 2 {
		t.Fatalf("inventory %+v", r)
	}
	v := leaves(r)["TestPay/one/nested"]
	if v.ID != "example/demo::TestPay/one/nested" || v.ParentID != "example/demo::TestPay/one" || v.Source.Kind != "subtest" || v.LineNumber < 1 || v.Digest == "" {
		t.Fatalf("metadata %+v", v)
	}
}
func TestTablesDirectAndLocal(t *testing.T) {
	for _, prefix := range []string{"for _, tc := range ", "cases := "} {
		body := prefix + `[]struct{name string; input int}{{"one",1},{name:"two", input:2}}`
		if prefix == "cases := " {
			body += "\nfor _, tc := range cases"
		}
		body += ` { t.Run(tc.name,func(t *testing.T){if tc.input==0 {t.Error("bad")}}) }`
		r := discover(t, source(body))
		l := leaves(r)
		if len(l) != 2 || l["TestPay/two"].Source.Kind != "table-row" {
			t.Fatalf("table %+v", r)
		}
	}
}
func TestRejectUnenumerableOrAmbiguous(t *testing.T) {
	for _, body := range []string{
		`t.Run(name,func(t *testing.T){})`,
		`for _, tc := range loadCases() { t.Run(tc.name,func(t *testing.T){}) }`,
		`t.Run("same",func(t *testing.T){});t.Run("same",func(t *testing.T){})`,
		`t.Run("a b",func(t *testing.T){});t.Run("a_b",func(t *testing.T){})`,
		`if enabled { t.Run("maybe",func(t *testing.T){}) }`,
		`cases:=[]struct{name string}{{"one"}}; cases=append(cases,struct{name string}{"two"}); for _,tc:=range cases {t.Run(tc.name,func(t *testing.T){})}`,
		`cases:=[]struct{name string}{{"one"}}; cases[0].name="two"; for _,tc:=range cases {t.Run(tc.name,func(t *testing.T){})}`,
	} {
		if _, err := scanSource("pkg", "x_test.go", []byte(source(body))); err == nil {
			t.Errorf("accepted %s", body)
		}
	}
}

func TestImportsAffectDigests(t *testing.T) {
	a := leaves(discover(t, source(`t.Error("red")`)))["TestPay"]
	b := leaves(discover(t, strings.Replace(source(`t.Error("red")`), `import "testing"`, `import("testing"; _ "net/http")`, 1)))["TestPay"]
	if a.Digest == b.Digest {
		t.Fatal("compiler relevant import change was ignored")
	}
}

func TestReferencedHelpersAndTestMainAffectDigests(t *testing.T) {
	base := source(`helper(t)`) + "\nfunc helper(t *testing.T){t.Error(\"red\")}\nfunc TestMain(m *testing.M){m.Run()}\n"
	a := leaves(discover(t, base))["TestPay"]
	b := leaves(discover(t, strings.Replace(base, `t.Error("red")`, `t.Error("changed")`, 1)))["TestPay"]
	c := leaves(discover(t, strings.Replace(base, `m.Run()`, `println("setup");m.Run()`, 1)))["TestPay"]
	if a.Digest == b.Digest || a.Digest == c.Digest {
		t.Fatal("shared test setup/helpers omitted")
	}
}
func table(rows, setup, callback string) string {
	return source(setup + `\n` + `for _, tc := range []struct{name string; input int; removedBy string}{` + rows + `} {t.Run(tc.name,func(t *testing.T){` + callback + `})}`)
}
func TestIndependentTableDigests(t *testing.T) {
	mk := func(rows, setup, callback string) map[string]Record {
		return leaves(discover(t, strings.ReplaceAll(table(rows, setup, callback), `\n`, "\n")))
	}
	a := mk(`{"one",1,""},{"two",2,""}`, `x:=1; _=x`, `if tc.input<1 {t.Error("red")}`)
	b := mk(`{"two",2,""},{"three",3,""},{"one",1,""}`, `x:=1; _=x`, `if tc.input<1 {t.Error("red")}`)
	if a["TestPay/one"].Digest != b["TestPay/one"].Digest || a["TestPay/two"].Digest != b["TestPay/two"].Digest {
		t.Fatal("adding/reordering rows changed siblings")
	}
	c := mk(`{"one",9,""},{"two",2,""}`, `x:=1; _=x`, `if tc.input<1 {t.Error("red")}`)
	if a["TestPay/one"].Digest == c["TestPay/one"].Digest || a["TestPay/two"].Digest != c["TestPay/two"].Digest {
		t.Fatal("row isolation")
	}
	d := mk(`{"one",1,""},{"two",2,""}`, `x:=2; _=x`, `if tc.input<1 {t.Error("red")}`)
	e := mk(`{"one",1,""},{"two",2,""}`, `x:=1; _=x`, `if tc.input<2 {t.Error("red")}`)
	if a["TestPay/one"].Digest == d["TestPay/one"].Digest || a["TestPay/two"].Digest == e["TestPay/two"].Digest {
		t.Fatal("shared body/setup omitted")
	}
}
func TestFormattingAndCompilerDirectives(t *testing.T) {
	a := leaves(discover(t, source(`t.Error("red")`)))["TestPay"]
	b := leaves(discover(t, source("// ordinary comment\n t.Error( \"red\" )")))["TestPay"]
	c := leaves(discover(t, "//go:build linux\n\n"+source(`t.Error("red")`)))["TestPay"]
	if a.Digest != b.Digest || a.Digest == c.Digest {
		t.Fatal("comment/directive treatment")
	}
}

func TestRowHelperDependenciesAreIndependent(t *testing.T) {
	base := strings.ReplaceAll(table(`{"one",1,""},{"two",2,""}`, "", `t.Error(tc.input)`), `\n`, "\n") + "\nfunc newInput() int{return 3}\n"
	a := leaves(discover(t, base))
	b := leaves(discover(t, strings.Replace(base, `{"two",2,""}`, `{"two",2,""},{"three",newInput(),""}`, 1)))
	if a["TestPay/one"].Digest != b["TestPay/one"].Digest || a["TestPay/two"].Digest != b["TestPay/two"].Digest {
		t.Fatal("new row helper changed sibling digests")
	}
}

func TestRejectOtherRunnableFormsAndRunAliases(t *testing.T) {
	for _, text := range []string{
		"package demo\nimport \"testing\"\nfunc FuzzPay(f *testing.F){f.Add(1)}",
		"package demo\nfunc ExamplePay(){println(1)\n// Output: 1\n}",
		source(`run:=t.Run;run("hidden",func(t *testing.T){})`),
		source(`register(t)`) + "\nfunc register(t *testing.T){t.Run(\"hidden\",func(t *testing.T){})}",
		source(`register(t)`) + "\nfunc register(t *testing.T){alias:=t;alias.Run(\"hidden\",func(t *testing.T){})}",
		"package demo\nimport(\"testing\";\"github.com/stretchr/testify/suite\")\nfunc TestSuite(t *testing.T){suite.Run(t, &MySuite{})}",
	} {
		if _, err := scanSource("pkg", "x_test.go", []byte(text)); err == nil {
			t.Errorf("accepted unsupported inventory: %s", text)
		}
	}
}
