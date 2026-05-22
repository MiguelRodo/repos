package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
)

// OrderedMap preserves the order of keys when decoding and encoding JSON.
type OrderedMap struct {
	Keys []string
	Vals map[string]any
}

func NewOrderedMap() *OrderedMap {
	return &OrderedMap{
		Keys: make([]string, 0),
		Vals: make(map[string]any),
	}
}

func (m *OrderedMap) Get(key string) (any, bool) {
	val, ok := m.Vals[key]
	return val, ok
}

func (m *OrderedMap) Set(key string, val any) {
	if _, ok := m.Vals[key]; !ok {
		m.Keys = append(m.Keys, key)
	}
	if m.Vals == nil {
		m.Vals = make(map[string]any)
	}
	m.Vals[key] = val
}

func (m *OrderedMap) MarshalJSON() ([]byte, error) {
	var buf bytes.Buffer
	buf.WriteByte('{')
	for i, k := range m.Keys {
		if i > 0 {
			buf.WriteByte(',')
		}
		kb, err := json.Marshal(k)
		if err != nil {
			return nil, err
		}
		buf.Write(kb)
		buf.WriteByte(':')
		vb, err := json.Marshal(m.Vals[k])
		if err != nil {
			return nil, err
		}
		buf.Write(vb)
	}
	buf.WriteByte('}')
	return buf.Bytes(), nil
}

// decodeValue parses a JSON token stream, preserving object order into OrderedMap.
func decodeValue(dec *json.Decoder) (any, error) {
	t, err := dec.Token()
	if err != nil {
		if err == io.EOF {
			return nil, nil
		}
		return nil, err
	}
	switch v := t.(type) {
	case json.Delim:
		if v == '{' {
			return decodeObject(dec)
		} else if v == '[' {
			return decodeArray(dec)
		}
		return nil, fmt.Errorf("unexpected delim %v", v)
	default:
		return v, nil
	}
}

func decodeObject(dec *json.Decoder) (*OrderedMap, error) {
	m := NewOrderedMap()
	for dec.More() {
		t, err := dec.Token()
		if err != nil {
			return nil, err
		}
		key, ok := t.(string)
		if !ok {
			return nil, fmt.Errorf("expected string key, got %T", t)
		}
		val, err := decodeValue(dec)
		if err != nil {
			return nil, err
		}
		m.Set(key, val)
	}
	// consume '}'
	_, err := dec.Token()
	return m, err
}

func decodeArray(dec *json.Decoder) ([]any, error) {
	var arr []any
	for dec.More() {
		val, err := decodeValue(dec)
		if err != nil {
			return nil, err
		}
		arr = append(arr, val)
	}
	// consume ']'
	_, err := dec.Token()
	return arr, err
}
