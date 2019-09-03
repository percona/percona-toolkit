package models

//go:generate ./gen.sh

type Name string

type Unknown []uint8

func (n Unknown) String() string {
	return string(n)
}
