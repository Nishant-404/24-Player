package gobackend

import "testing"

func TestExtractAmazonASIN(t *testing.T) {
	tests := []struct {
		name string
		url  string
		want string
	}{
		{
			name: "prefers trackAsin over albumAsin",
			url:  "https://music.amazon.com/albums/B0ALBUM123?trackAsin=B0TRACK456&musicTerritory=US",
			want: "B0TRACK456",
		},
		{
			name: "extract from tracks path",
			url:  "https://music.amazon.com/tracks/B0CYQHGWZJ?musicTerritory=US",
			want: "B0CYQHGWZJ",
		},
		{
			name: "extract from plain query asin",
			url:  "https://example.com/?asin=B0CYQHGWZJ",
			want: "B0CYQHGWZJ",
		},
		{
			name: "fallback regex",
			url:  "https://example.com/path/B0CYQHGWZJ",
			want: "B0CYQHGWZJ",
		},
		{
			name: "invalid url",
			url:  "https://music.amazon.com/tracks/not-valid",
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractAmazonASIN(tt.url)
			if got != tt.want {
				t.Fatalf("extractAmazonASIN() = %q, want %q", got, tt.want)
			}
		})
	}
}
