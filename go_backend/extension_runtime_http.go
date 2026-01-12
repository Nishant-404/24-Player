// Package gobackend provides HTTP API for extension runtime
package gobackend

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/dop251/goja"
)

// ==================== HTTP API (Sandboxed) ====================

// HTTPResponse represents the response from an HTTP request
type HTTPResponse struct {
	StatusCode int               `json:"statusCode"`
	Body       string            `json:"body"`
	Headers    map[string]string `json:"headers"`
}

// validateDomain checks if the domain is allowed by the extension's permissions
func (r *ExtensionRuntime) validateDomain(urlStr string) error {
	parsed, err := url.Parse(urlStr)
	if err != nil {
		return fmt.Errorf("invalid URL: %w", err)
	}

	domain := parsed.Hostname()
	if !r.manifest.IsDomainAllowed(domain) {
		return fmt.Errorf("network access denied: domain '%s' not in allowed list", domain)
	}

	return nil
}

// httpGet performs a GET request (sandboxed)
func (r *ExtensionRuntime) httpGet(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"error": "URL is required",
		})
	}

	urlStr := call.Arguments[0].String()

	// Validate domain
	if err := r.validateDomain(urlStr); err != nil {
		GoLog("[Extension:%s] HTTP blocked: %v\n", r.extensionID, err)
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Get headers if provided
	headers := make(map[string]string)
	if len(call.Arguments) > 1 && !goja.IsUndefined(call.Arguments[1]) && !goja.IsNull(call.Arguments[1]) {
		headersObj := call.Arguments[1].Export()
		if h, ok := headersObj.(map[string]interface{}); ok {
			for k, v := range h {
				headers[k] = fmt.Sprintf("%v", v)
			}
		}
	}

	// Create request
	req, err := http.NewRequest("GET", urlStr, nil)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Set headers - user headers first
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	// Only set default User-Agent if not provided by extension
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "Spotiflac-Extension/1.0")
	}

	// Execute request
	resp, err := r.httpClient.Do(req)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}
	defer resp.Body.Close()

	// Read body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Extract response headers - return all values as arrays for multi-value headers (cookies, etc.)
	respHeaders := make(map[string]interface{})
	for k, v := range resp.Header {
		if len(v) == 1 {
			respHeaders[k] = v[0]
		} else {
			respHeaders[k] = v // Return as array if multiple values
		}
	}

	return r.vm.ToValue(map[string]interface{}{
		"statusCode": resp.StatusCode,
		"status":     resp.StatusCode, // Alias for convenience
		"ok":         resp.StatusCode >= 200 && resp.StatusCode < 300,
		"body":       string(body),
		"headers":    respHeaders,
	})
}

// httpPost performs a POST request (sandboxed)
func (r *ExtensionRuntime) httpPost(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"error": "URL is required",
		})
	}

	urlStr := call.Arguments[0].String()

	// Validate domain
	if err := r.validateDomain(urlStr); err != nil {
		GoLog("[Extension:%s] HTTP blocked: %v\n", r.extensionID, err)
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Get body if provided - support both string and object
	var bodyStr string
	if len(call.Arguments) > 1 && !goja.IsUndefined(call.Arguments[1]) && !goja.IsNull(call.Arguments[1]) {
		bodyArg := call.Arguments[1].Export()
		switch v := bodyArg.(type) {
		case string:
			bodyStr = v
		case map[string]interface{}, []interface{}:
			// Auto-stringify objects and arrays to JSON
			jsonBytes, err := json.Marshal(v)
			if err != nil {
				return r.vm.ToValue(map[string]interface{}{
					"error": fmt.Sprintf("failed to stringify body: %v", err),
				})
			}
			bodyStr = string(jsonBytes)
		default:
			// Fallback to string conversion
			bodyStr = call.Arguments[1].String()
		}
	}

	// Get headers if provided
	headers := make(map[string]string)
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
		headersObj := call.Arguments[2].Export()
		if h, ok := headersObj.(map[string]interface{}); ok {
			for k, v := range h {
				headers[k] = fmt.Sprintf("%v", v)
			}
		}
	}

	// Create request
	req, err := http.NewRequest("POST", urlStr, strings.NewReader(bodyStr))
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Set headers - user headers first
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	// Only set defaults if not provided by extension
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "Spotiflac-Extension/1.0")
	}
	if req.Header.Get("Content-Type") == "" {
		req.Header.Set("Content-Type", "application/json")
	}

	// Execute request
	resp, err := r.httpClient.Do(req)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}
	defer resp.Body.Close()

	// Read body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Extract response headers - return all values as arrays for multi-value headers
	respHeaders := make(map[string]interface{})
	for k, v := range resp.Header {
		if len(v) == 1 {
			respHeaders[k] = v[0]
		} else {
			respHeaders[k] = v // Return as array if multiple values
		}
	}

	return r.vm.ToValue(map[string]interface{}{
		"statusCode": resp.StatusCode,
		"status":     resp.StatusCode, // Alias for convenience
		"ok":         resp.StatusCode >= 200 && resp.StatusCode < 300,
		"body":       string(body),
		"headers":    respHeaders,
	})
}

// httpRequest performs a generic HTTP request (GET, POST, PUT, DELETE, etc.)
// Usage: http.request(url, options) where options = { method, body, headers }
func (r *ExtensionRuntime) httpRequest(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"error": "URL is required",
		})
	}

	urlStr := call.Arguments[0].String()

	// Validate domain
	if err := r.validateDomain(urlStr); err != nil {
		GoLog("[Extension:%s] HTTP blocked: %v\n", r.extensionID, err)
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Default options
	method := "GET"
	var bodyStr string
	headers := make(map[string]string)

	// Parse options if provided
	if len(call.Arguments) > 1 && !goja.IsUndefined(call.Arguments[1]) && !goja.IsNull(call.Arguments[1]) {
		optionsObj := call.Arguments[1].Export()
		if opts, ok := optionsObj.(map[string]interface{}); ok {
			// Get method
			if m, ok := opts["method"].(string); ok {
				method = strings.ToUpper(m)
			}

			// Get body - support both string and object
			if bodyArg, ok := opts["body"]; ok && bodyArg != nil {
				switch v := bodyArg.(type) {
				case string:
					bodyStr = v
				case map[string]interface{}, []interface{}:
					// Auto-stringify objects and arrays to JSON
					jsonBytes, err := json.Marshal(v)
					if err != nil {
						return r.vm.ToValue(map[string]interface{}{
							"error": fmt.Sprintf("failed to stringify body: %v", err),
						})
					}
					bodyStr = string(jsonBytes)
				default:
					bodyStr = fmt.Sprintf("%v", v)
				}
			}

			// Get headers
			if h, ok := opts["headers"].(map[string]interface{}); ok {
				for k, v := range h {
					headers[k] = fmt.Sprintf("%v", v)
				}
			}
		}
	}

	// Create request
	var reqBody io.Reader
	if bodyStr != "" {
		reqBody = strings.NewReader(bodyStr)
	}

	req, err := http.NewRequest(method, urlStr, reqBody)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Set headers - user headers first
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	// Only set defaults if not provided by extension
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "Spotiflac-Extension/1.0")
	}
	if bodyStr != "" && req.Header.Get("Content-Type") == "" {
		req.Header.Set("Content-Type", "application/json")
	}

	// Execute request
	resp, err := r.httpClient.Do(req)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}
	defer resp.Body.Close()

	// Read body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Extract response headers - return all values as arrays for multi-value headers
	respHeaders := make(map[string]interface{})
	for k, v := range resp.Header {
		if len(v) == 1 {
			respHeaders[k] = v[0]
		} else {
			respHeaders[k] = v // Return as array if multiple values
		}
	}

	// Return response with helper properties
	return r.vm.ToValue(map[string]interface{}{
		"statusCode": resp.StatusCode,
		"status":     resp.StatusCode, // Alias for convenience
		"ok":         resp.StatusCode >= 200 && resp.StatusCode < 300,
		"body":       string(body),
		"headers":    respHeaders,
	})
}

// httpPut performs a PUT request (shortcut for http.request with method: "PUT")
func (r *ExtensionRuntime) httpPut(call goja.FunctionCall) goja.Value {
	return r.httpMethodShortcut("PUT", call)
}

// httpDelete performs a DELETE request (shortcut for http.request with method: "DELETE")
func (r *ExtensionRuntime) httpDelete(call goja.FunctionCall) goja.Value {
	return r.httpMethodShortcut("DELETE", call)
}

// httpPatch performs a PATCH request (shortcut for http.request with method: "PATCH")
func (r *ExtensionRuntime) httpPatch(call goja.FunctionCall) goja.Value {
	return r.httpMethodShortcut("PATCH", call)
}

// httpMethodShortcut is a helper for PUT/DELETE/PATCH shortcuts
// Signature: http.put(url, body, headers) / http.delete(url, headers) / http.patch(url, body, headers)
func (r *ExtensionRuntime) httpMethodShortcut(method string, call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"error": "URL is required",
		})
	}

	urlStr := call.Arguments[0].String()

	// Validate domain
	if err := r.validateDomain(urlStr); err != nil {
		GoLog("[Extension:%s] HTTP blocked: %v\n", r.extensionID, err)
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	var bodyStr string
	headers := make(map[string]string)

	// For DELETE, second arg is headers; for PUT/PATCH, second arg is body
	if method == "DELETE" {
		// http.delete(url, headers)
		if len(call.Arguments) > 1 && !goja.IsUndefined(call.Arguments[1]) && !goja.IsNull(call.Arguments[1]) {
			headersObj := call.Arguments[1].Export()
			if h, ok := headersObj.(map[string]interface{}); ok {
				for k, v := range h {
					headers[k] = fmt.Sprintf("%v", v)
				}
			}
		}
	} else {
		// http.put(url, body, headers) / http.patch(url, body, headers)
		if len(call.Arguments) > 1 && !goja.IsUndefined(call.Arguments[1]) && !goja.IsNull(call.Arguments[1]) {
			bodyArg := call.Arguments[1].Export()
			switch v := bodyArg.(type) {
			case string:
				bodyStr = v
			case map[string]interface{}, []interface{}:
				jsonBytes, err := json.Marshal(v)
				if err != nil {
					return r.vm.ToValue(map[string]interface{}{
						"error": fmt.Sprintf("failed to stringify body: %v", err),
					})
				}
				bodyStr = string(jsonBytes)
			default:
				bodyStr = call.Arguments[1].String()
			}
		}

		if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
			headersObj := call.Arguments[2].Export()
			if h, ok := headersObj.(map[string]interface{}); ok {
				for k, v := range h {
					headers[k] = fmt.Sprintf("%v", v)
				}
			}
		}
	}

	// Create request
	var reqBody io.Reader
	if bodyStr != "" {
		reqBody = strings.NewReader(bodyStr)
	}

	req, err := http.NewRequest(method, urlStr, reqBody)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Set headers - user headers first
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", "Spotiflac-Extension/1.0")
	}
	if bodyStr != "" && req.Header.Get("Content-Type") == "" {
		req.Header.Set("Content-Type", "application/json")
	}

	// Execute request
	resp, err := r.httpClient.Do(req)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}
	defer resp.Body.Close()

	// Read body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"error": err.Error(),
		})
	}

	// Extract response headers
	respHeaders := make(map[string]interface{})
	for k, v := range resp.Header {
		if len(v) == 1 {
			respHeaders[k] = v[0]
		} else {
			respHeaders[k] = v
		}
	}

	return r.vm.ToValue(map[string]interface{}{
		"statusCode": resp.StatusCode,
		"status":     resp.StatusCode,
		"ok":         resp.StatusCode >= 200 && resp.StatusCode < 300,
		"body":       string(body),
		"headers":    respHeaders,
	})
}

// httpClearCookies clears all cookies for this extension
func (r *ExtensionRuntime) httpClearCookies(call goja.FunctionCall) goja.Value {
	if jar, ok := r.cookieJar.(*simpleCookieJar); ok {
		jar.mu.Lock()
		jar.cookies = make(map[string][]*http.Cookie)
		jar.mu.Unlock()
		GoLog("[Extension:%s] Cookies cleared\n", r.extensionID)
		return r.vm.ToValue(true)
	}
	return r.vm.ToValue(false)
}
