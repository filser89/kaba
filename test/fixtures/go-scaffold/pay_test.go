package demo
import "testing"
func TestExisting(t *testing.T) { if OldBehavior()!=42 { t.Fatal("old behavior replaced") } }
func TestMissingType(t *testing.T) { if New().Value!=9 { t.Fatal("expected real new API") } }
func TestMissingMethod(t *testing.T) { if (Old{}).Missing()!=9 { t.Fatal("expected real method") } }
func TestMissingField(t *testing.T) { if NewOld().Added!=9 { t.Fatal("expected initialized field") } }
func TestZero(t *testing.T) { if Zero()!=0 { t.Fatal("zero contract") } }
