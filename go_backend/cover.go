package gobackend

import (
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
)

// Spotify image size codes (same as PC version)
const (
	spotifySize300 = "ab67616d00001e02" // 300x300 (small)
	spotifySize640 = "ab67616d0000b273" // 640x640 (medium)
	spotifySizeMax = "ab67616d000082c1" // Max resolution (~2000x2000)
)

// Deezer CDN supports these sizes: 56, 250, 500, 1000, 1400, 1800
var deezerSizeRegex = regexp.MustCompile(`/(\d+)x(\d+)-\d+-\d+-\d+-\d+\.jpg$`)

// convertSmallToMedium upgrades 300x300 cover URL to 640x640
// Same logic as PC version for consistency
func convertSmallToMedium(imageURL string) string {
	if strings.Contains(imageURL, spotifySize300) {
		return strings.Replace(imageURL, spotifySize300, spotifySize640, 1)
	}
	return imageURL
}

// downloadCoverToMemory downloads cover art and returns as bytes (no file creation)
// This avoids file permission issues on Android
func downloadCoverToMemory(coverURL string, maxQuality bool) ([]byte, error) {
	if coverURL == "" {
		return nil, fmt.Errorf("no cover URL provided")
	}

	GoLog("[Cover] Original URL: %s", coverURL)

	downloadURL := convertSmallToMedium(coverURL)
	if downloadURL != coverURL {
		GoLog("[Cover] Upgraded 300x300 → 640x640")
	}

	if maxQuality {
		maxURL := upgradeToMaxQuality(downloadURL)
		if maxURL != downloadURL {
			downloadURL = maxURL
			// Log already printed by upgradeToMaxQuality for Deezer
			if strings.Contains(coverURL, "scdn.co") || strings.Contains(coverURL, "spotifycdn") {
				GoLog("[Cover] Spotify: upgraded to max resolution (~2000x2000)")
			}
		}
	}

	GoLog("[Cover] Final URL: %s", downloadURL)

	client := NewHTTPClientWithTimeout(DefaultTimeout)

	req, err := http.NewRequest("GET", downloadURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := DoRequestWithUserAgent(client, req)
	if err != nil {
		return nil, fmt.Errorf("failed to download cover: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("cover download failed: HTTP %d", resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read cover data: %w", err)
	}

	sizeKB := len(data) / 1024
	var resolution string
	if sizeKB > 200 {
		resolution = "~2000x2000 (hi-res)"
	} else if sizeKB > 50 {
		resolution = "~640x640"
	} else {
		resolution = "~300x300"
	}
	GoLog("[Cover] Downloaded %d KB (%s)", sizeKB, resolution)

	return data, nil
}

// upgradeToMaxQuality upgrades cover URL to maximum quality
// Supports both Spotify and Deezer CDNs
func upgradeToMaxQuality(coverURL string) string {
	// Spotify CDN upgrade
	if strings.Contains(coverURL, spotifySize640) {
		return strings.Replace(coverURL, spotifySize640, spotifySizeMax, 1)
	}

	// Deezer CDN upgrade
	if strings.Contains(coverURL, "cdn-images.dzcdn.net") {
		return upgradeDeezerCover(coverURL)
	}

	return coverURL
}

// upgradeDeezerCover upgrades Deezer cover URL to maximum quality (1800x1800)
// Deezer CDN format: https://cdn-images.dzcdn.net/images/cover/{hash}/{size}x{size}-000000-80-0-0.jpg
// Available sizes: 56, 250, 500, 1000, 1400, 1800
func upgradeDeezerCover(coverURL string) string {
	if !strings.Contains(coverURL, "cdn-images.dzcdn.net") {
		return coverURL
	}

	// Replace any size pattern with 1800x1800
	upgraded := deezerSizeRegex.ReplaceAllString(coverURL, "/1800x1800-000000-80-0-0.jpg")
	if upgraded != coverURL {
		GoLog("[Cover] Deezer: upgraded to 1800x1800")
	}
	return upgraded
}

// GetCoverFromSpotify gets cover URL from Spotify metadata
func GetCoverFromSpotify(imageURL string, maxQuality bool) string {
	if imageURL == "" {
		return ""
	}

	// Always upgrade small to medium first
	result := convertSmallToMedium(imageURL)

	if maxQuality {
		result = upgradeToMaxQuality(result)
	}

	return result
}
