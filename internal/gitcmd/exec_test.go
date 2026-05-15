package gitcmd

import "testing"

func TestSanitizeURL(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "plain URL",
			in:   "https://github.com/path",
			want: "https://github.com/path",
		},
		{
			name: "simple credentials",
			in:   "https://user:password@github.com/path",
			want: "https://github.com/path",
		},
		{
			name: "multiple @ in credentials",
			in:   "https://user:p@ss@github.com/path",
			want: "https://github.com/path",
		},
		{
			name: "token in credentials",
			in:   "https://ghp_abcdef@github.com/path",
			want: "https://github.com/path",
		},
		{
			name: "non-http string",
			in:   "git clone https://user:password@github.com/path",
			want: "git clone https://github.com/path",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := SanitizeURL(tt.in)
			if got != tt.want {
				t.Errorf("SanitizeURL(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}
