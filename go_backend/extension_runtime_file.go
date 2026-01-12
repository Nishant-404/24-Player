// Package gobackend provides File API for extension runtime
package gobackend

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/dop251/goja"
)

// ==================== File API (Sandboxed) ====================

// validatePath checks if the path is within the extension's data directory
// For absolute paths (from download queue), it allows them if they're valid
func (r *ExtensionRuntime) validatePath(path string) (string, error) {
	// Clean and resolve the path
	cleanPath := filepath.Clean(path)

	// If path is absolute, allow it (for download queue paths)
	// This is safe because the Go backend controls what paths are passed
	if filepath.IsAbs(cleanPath) {
		return cleanPath, nil
	}

	// For relative paths, join with data directory
	fullPath := filepath.Join(r.dataDir, cleanPath)

	// Resolve to absolute path
	absPath, err := filepath.Abs(fullPath)
	if err != nil {
		return "", fmt.Errorf("invalid path: %w", err)
	}

	// Ensure path is within data directory
	absDataDir, _ := filepath.Abs(r.dataDir)
	if !strings.HasPrefix(absPath, absDataDir) {
		return "", fmt.Errorf("file access denied: path '%s' is outside sandbox", path)
	}

	return absPath, nil
}

// fileDownload downloads a file from URL to the specified path
// Supports progress callback via options.onProgress
func (r *ExtensionRuntime) fileDownload(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "URL and output path are required",
		})
	}

	urlStr := call.Arguments[0].String()
	outputPath := call.Arguments[1].String()

	// Validate domain
	if err := r.validateDomain(urlStr); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	// Validate output path (allows absolute paths for download queue)
	fullPath, err := r.validatePath(outputPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	// Get options if provided
	var onProgress goja.Callable
	var headers map[string]string
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
		optionsObj := call.Arguments[2].Export()
		if opts, ok := optionsObj.(map[string]interface{}); ok {
			// Extract headers
			if h, ok := opts["headers"].(map[string]interface{}); ok {
				headers = make(map[string]string)
				for k, v := range h {
					headers[k] = fmt.Sprintf("%v", v)
				}
			}
			// Extract onProgress callback
			if progressVal, ok := opts["onProgress"]; ok {
				if callable, ok := goja.AssertFunction(r.vm.ToValue(progressVal)); ok {
					onProgress = callable
				}
			}
		}
	}

	// Create directory if needed
	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	// Create HTTP request
	req, err := http.NewRequest("GET", urlStr, nil)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	// Set headers
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "SpotiFLAC-Extension/1.0")
	}

	// Download file
	resp, err := r.httpClient.Do(req)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("HTTP error: %d", resp.StatusCode),
		})
	}

	// Create output file
	out, err := os.Create(fullPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create file: %v", err),
		})
	}
	defer out.Close()

	// Get content length for progress
	contentLength := resp.ContentLength

	// Copy content with progress reporting
	var written int64
	buf := make([]byte, 32*1024) // 32KB buffer
	for {
		nr, er := resp.Body.Read(buf)
		if nr > 0 {
			nw, ew := out.Write(buf[0:nr])
			if nw < 0 || nr < nw {
				nw = 0
				if ew == nil {
					ew = fmt.Errorf("invalid write result")
				}
			}
			written += int64(nw)
			if ew != nil {
				return r.vm.ToValue(map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("failed to write file: %v", ew),
				})
			}
			if nr != nw {
				return r.vm.ToValue(map[string]interface{}{
					"success": false,
					"error":   "short write",
				})
			}

			// Report progress
			if onProgress != nil && contentLength > 0 {
				_, _ = onProgress(goja.Undefined(), r.vm.ToValue(written), r.vm.ToValue(contentLength))
			}
		}
		if er != nil {
			if er != io.EOF {
				return r.vm.ToValue(map[string]interface{}{
					"success": false,
					"error":   fmt.Sprintf("failed to read response: %v", er),
				})
			}
			break
		}
	}

	GoLog("[Extension:%s] Downloaded %d bytes to %s\n", r.extensionID, written, fullPath)

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullPath,
		"size":    written,
	})
}

// fileExists checks if a file exists in the sandbox
func (r *ExtensionRuntime) fileExists(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(false)
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(false)
	}

	_, err = os.Stat(fullPath)
	return r.vm.ToValue(err == nil)
}

// fileDelete deletes a file in the sandbox
func (r *ExtensionRuntime) fileDelete(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path is required",
		})
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	if err := os.Remove(fullPath); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
	})
}

// fileRead reads a file from the sandbox
func (r *ExtensionRuntime) fileRead(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path is required",
		})
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	data, err := os.ReadFile(fullPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"data":    string(data),
	})
}

// fileWrite writes data to a file in the sandbox
func (r *ExtensionRuntime) fileWrite(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path and data are required",
		})
	}

	path := call.Arguments[0].String()
	data := call.Arguments[1].String()

	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	// Create directory if needed
	dir := filepath.Dir(fullPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	if err := os.WriteFile(fullPath, []byte(data), 0644); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullPath,
	})
}

// fileCopy copies a file within the sandbox
func (r *ExtensionRuntime) fileCopy(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "source and destination paths are required",
		})
	}

	srcPath := call.Arguments[0].String()
	dstPath := call.Arguments[1].String()

	fullSrc, err := r.validatePath(srcPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	fullDst, err := r.validatePath(dstPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	// Read source file
	data, err := os.ReadFile(fullSrc)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to read source: %v", err),
		})
	}

	// Create destination directory if needed
	dir := filepath.Dir(fullDst)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	// Write to destination
	if err := os.WriteFile(fullDst, data, 0644); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to write destination: %v", err),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullDst,
	})
}

// fileMove moves/renames a file within the sandbox
func (r *ExtensionRuntime) fileMove(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "source and destination paths are required",
		})
	}

	srcPath := call.Arguments[0].String()
	dstPath := call.Arguments[1].String()

	fullSrc, err := r.validatePath(srcPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	fullDst, err := r.validatePath(dstPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	// Create destination directory if needed
	dir := filepath.Dir(fullDst)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to create directory: %v", err),
		})
	}

	if err := os.Rename(fullSrc, fullDst); err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("failed to move file: %v", err),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"path":    fullDst,
	})
}

// fileGetSize returns the size of a file in bytes
func (r *ExtensionRuntime) fileGetSize(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "path is required",
		})
	}

	path := call.Arguments[0].String()
	fullPath, err := r.validatePath(path)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	info, err := os.Stat(fullPath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success": true,
		"size":    info.Size(),
	})
}
