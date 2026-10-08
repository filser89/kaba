package main

import (
	"strings"
	"testing"
)

func TestCleanupExactFunction(t *testing.T) {
	src := []byte("package p\nimport \"testing\"\nfunc TestGone(t *testing.T){t.Skip(\"REMOVED by one\")}\nfunc TestKeep(t *testing.T){}\n")
	records, err := scanSource("p", "x_test.go", src)
	if err != nil {
		t.Fatal(err)
	}
	edits, ids, err := planGoRemovals(src, records, map[string]string{"p::TestGone": "pending", "p::TestKeep": "passed"}, "one")
	if err != nil {
		t.Fatal(err)
	}
	if len(edits) != 1 || len(ids) != 1 {
		t.Fatalf("wrong removal %+v %v", edits, ids)
	}
	got, err := applyGoEdits(src, edits)
	if err != nil || strings.Contains(string(got), "TestGone") || !strings.Contains(string(got), "func TestKeep(t *testing.T){}") {
		t.Fatalf("%s %v", got, err)
	}
	_, _, err = planGoRemovals(src, records, map[string]string{"p::TestGone": "passed"}, "one")
	if err == nil {
		t.Fatal("requires observed pending")
	}
}
func TestCleanupExactRow(t *testing.T) {
	src := []byte(`package p
import "testing"
func TestRows(t *testing.T){
 cases:=[]struct{name string;removedBy string}{{"first",""},{"gone","one"},{"last",""}}
 for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){if tc.removedBy!=""{t.Skip("REMOVED by "+tc.removedBy)}})}
}
`)
	records, err := scanSource("p", "x_test.go", src)
	if err != nil {
		t.Fatal(err)
	}
	edits, ids, err := planGoRemovals(src, records, map[string]string{"p::TestRows/first": "passed", "p::TestRows/gone": "pending", "p::TestRows/last": "passed"}, "one")
	if err != nil {
		t.Fatal(err)
	}
	got, err := applyGoEdits(src, edits)
	if err != nil || len(ids) != 1 || strings.Contains(string(got), `{"gone","one"}`) || !strings.Contains(string(got), `{"first",""},{"last",""}`) {
		t.Fatalf("%s %v", got, err)
	}
	next, err := scanSource("p", "x_test.go", got)
	if err != nil || len(next) != 3 {
		t.Fatalf("wrong remaining %v %v", next, err)
	}
}
func TestCleanupRefusesLastRow(t *testing.T) {
	src := []byte(`package p
import "testing"
func TestRows(t *testing.T){for _,tc:=range []struct{name string;removedBy string}{{"gone","one"}}{t.Run(tc.name,func(t *testing.T){if tc.removedBy!=""{t.Skip("REMOVED by "+tc.removedBy)}})}}`)
	records, err := scanSource("p", "x_test.go", src)
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = planGoRemovals(src, records, map[string]string{"p::TestRows/gone": "pending"}, "one")
	if err == nil {
		t.Fatal("last row must not expose parent identity")
	}
}

func TestCleanupKeyedRowsMayOmitRemovalField(t *testing.T) {
	src := []byte(`package p
import "testing"
func TestRows(t *testing.T){
 cases:=[]struct{name string;removedBy string;input int}{{name:"keep",input:1},{name:"gone",removedBy:"one",input:2},{name:"last",input:3}}
 for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){if tc.removedBy!=""{t.Skip("REMOVED by "+tc.removedBy)}})}
}
`)
	records, err := scanSource("p", "x_test.go", src)
	if err != nil {
		t.Fatal(err)
	}
	edits, ids, err := planGoRemovals(src, records, map[string]string{"p::TestRows/keep": "passed", "p::TestRows/gone": "pending", "p::TestRows/last": "passed"}, "one")
	if err != nil {
		t.Fatal(err)
	}
	got, err := applyGoEdits(src, edits)
	if err != nil || len(ids) != 1 || ids[0] != "p::TestRows/gone" || strings.Contains(string(got), `name:"gone"`) || !strings.Contains(string(got), `{name:"keep",input:1},{name:"last",input:3}`) {
		t.Fatalf("unexpected removal %s %v %v", got, ids, err)
	}
}

func TestCleanupExactLiteralSubtest(t *testing.T) {
	src := []byte(`package p
import "testing"
func TestGroup(t *testing.T){t.Run("gone",func(t *testing.T){t.Skip("REMOVED by one")});t.Run("keep",func(t *testing.T){})}`)
	records, err := scanSource("p", "x_test.go", src)
	if err != nil {
		t.Fatal(err)
	}
	edits, ids, err := planGoRemovals(src, records, map[string]string{"p::TestGroup/gone": "pending", "p::TestGroup/keep": "passed"}, "one")
	if err != nil {
		t.Fatal(err)
	}
	got, err := applyGoEdits(src, edits)
	if err != nil || len(ids) != 1 || strings.Contains(string(got), `"gone"`) || !strings.Contains(string(got), `t.Run("keep",func(t *testing.T){})`) {
		t.Fatalf("%s %v", got, err)
	}
}
func TestCleanupRefusesDynamicRemovalFeature(t *testing.T) {
	src := []byte(`package p
import "testing"
func TestRows(t *testing.T){feature:="one";for _,tc:=range []struct{name string;removedBy string}{{"gone",feature},{"keep",""}}{t.Run(tc.name,func(t *testing.T){if tc.removedBy!=""{t.Skip("REMOVED by "+tc.removedBy)}})}}`)
	records, err := scanSource("p", "x_test.go", src)
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = planGoRemovals(src, records, map[string]string{"p::TestRows/gone": "pending", "p::TestRows/keep": "passed"}, "one")
	if err == nil {
		t.Fatal("dynamic removal feature must fail closed")
	}
}
