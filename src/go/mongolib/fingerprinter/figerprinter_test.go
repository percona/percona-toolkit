package fingerprinter

import "testing"

func TestFingerprint(t *testing.T) {

	query := map[string]interface{}{
		"find": "feedback",
		"filter": map[string]interface{}{
			"tool":  "Atlas",
			"potId": "2c9180865ae33e85015af1cc29243dc5",
		},
		"limit":       1,
		"singleBatch": true,
	}
	want := "potId,tool"

	fp := NewFingerprinter(nil)
	got, err := fp.Fingerprint(query)

	if err != nil {
		t.Error("Error in fingerprint")
	}

	if got != want {
		t.Errorf("Invalid fingerprint. Got: %q, want %q", got, want)
	}

}
