package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestOrderedMap(t *testing.T) {
	in := `{"image": "ghcr.io/m", "customizations": {"codespaces": {"repositories": {}}, "vscode": {}}}`
	dec := json.NewDecoder(strings.NewReader(in))
	dec.UseNumber()
	val, err := decodeValue(dec)
	if err != nil {
		t.Fatal(err)
	}

	out, err := json.MarshalIndent(val, "", "  ")
	if err != nil {
		t.Fatal(err)
	}

	expected := `{
  "image": "ghcr.io/m",
  "customizations": {
    "codespaces": {
      "repositories": {}
    },
    "vscode": {}
  }
}`
	if string(out) != expected {
		t.Errorf("expected:\n%s\ngot:\n%s", expected, string(out))
	}
}
