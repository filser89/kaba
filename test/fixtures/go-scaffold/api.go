package demo

type Need struct { Value int }
func New() Need { var zero Need; return zero }
func (o Old) Missing() int { return 0 }
type Old struct { Added int }
func NewOld() Old { var zero Old; return zero }
func Zero() int { return 0 }
