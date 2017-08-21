package proto

import (
	"bytes"
	"encoding/json"
	"fmt"

	"gopkg.in/mgo.v2/bson"
)

type BsonD struct {
	bson.D
}

func (d *BsonD) UnmarshalJSON(data []byte) error {
	dec := json.NewDecoder(bytes.NewReader(data))

	t, err := dec.Token()
	if err != nil {
		return err
	}
	if t != json.Delim('{') {
		return fmt.Errorf("expected { but got %s", t)
	}
	for {
		t, err := dec.Token()
		if err != nil {
			return err
		}

		// Might be empty object
		if t == json.Delim('}') {
			return nil
		}

		key, ok := t.(string)
		if !ok {
			return fmt.Errorf("expected key to be a string but got %s", t)
		}

		de := bson.DocElem{}
		de.Name = key

		if !dec.More() {
			return fmt.Errorf("missing value for key %s", key)
		}

		v := BsonD{}
		r := dec.Buffered()
		ndec := json.NewDecoder(r)
		err = ndec.Decode(&v)
		if err != nil {
			var v interface{}
			dec.Decode(&v)
			de.Value = v
		} else {
			de.Value = v
		}

		d.D = append(d.D, de)
		if !dec.More() {
			break
		}
	}

	t, err = dec.Token()
	if err != nil {
		return err
	}
	if t != json.Delim('}') {
		return fmt.Errorf("expect delimeter %s but got %s", json.Delim('}'), t)
	}

	return nil
}

func (d *BsonD) MarshalJSON() ([]byte, error) {
	var b bytes.Buffer
	if d.D == nil {
		b.WriteString("null")
		return nil, nil
	}

	b.WriteByte('{')

	for i, v := range d.D {
		if i > 0 {
			b.WriteByte(',')
		}

		// marshal key
		key, err := json.Marshal(v.Name)
		if err != nil {
			return nil, err
		}
		b.Write(key)
		b.WriteByte(':')

		// marshal value
		val, err := json.Marshal(v.Value)
		if err != nil {
			return nil, err
		}
		b.Write(val)
	}

	b.WriteByte('}')

	return b.Bytes(), nil
}

func (d BsonD) Len() int {
	return len(d.D)
}
