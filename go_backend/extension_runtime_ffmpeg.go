// Package gobackend provides FFmpeg API for extension runtime
package gobackend

import (
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/dop251/goja"
)

// ==================== FFmpeg API (Post-Processing) ====================

// FFmpegCommand holds a pending FFmpeg command for Flutter to execute
type FFmpegCommand struct {
	ExtensionID string
	Command     string
	InputPath   string
	OutputPath  string
	Completed   bool
	Success     bool
	Error       string
	Output      string
}

// Global FFmpeg command queue
var (
	ffmpegCommands   = make(map[string]*FFmpegCommand)
	ffmpegCommandsMu sync.RWMutex
	ffmpegCommandID  int64
)

// GetPendingFFmpegCommand returns a pending FFmpeg command (called from Flutter)
func GetPendingFFmpegCommand(commandID string) *FFmpegCommand {
	ffmpegCommandsMu.RLock()
	defer ffmpegCommandsMu.RUnlock()
	return ffmpegCommands[commandID]
}

// SetFFmpegCommandResult sets the result of an FFmpeg command (called from Flutter)
func SetFFmpegCommandResult(commandID string, success bool, output, errorMsg string) {
	ffmpegCommandsMu.Lock()
	defer ffmpegCommandsMu.Unlock()
	if cmd, exists := ffmpegCommands[commandID]; exists {
		cmd.Completed = true
		cmd.Success = success
		cmd.Output = output
		cmd.Error = errorMsg
	}
}

// ClearFFmpegCommand removes a completed FFmpeg command
func ClearFFmpegCommand(commandID string) {
	ffmpegCommandsMu.Lock()
	defer ffmpegCommandsMu.Unlock()
	delete(ffmpegCommands, commandID)
}

// ffmpegExecute queues an FFmpeg command for execution by Flutter
func (r *ExtensionRuntime) ffmpegExecute(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "command is required",
		})
	}

	command := call.Arguments[0].String()

	// Generate unique command ID
	ffmpegCommandsMu.Lock()
	ffmpegCommandID++
	cmdID := fmt.Sprintf("%s_%d", r.extensionID, ffmpegCommandID)
	ffmpegCommands[cmdID] = &FFmpegCommand{
		ExtensionID: r.extensionID,
		Command:     command,
		Completed:   false,
	}
	ffmpegCommandsMu.Unlock()

	GoLog("[Extension:%s] FFmpeg command queued: %s\n", r.extensionID, cmdID)

	// Wait for completion (with timeout)
	timeout := 5 * time.Minute
	start := time.Now()
	for {
		ffmpegCommandsMu.RLock()
		cmd := ffmpegCommands[cmdID]
		completed := cmd != nil && cmd.Completed
		ffmpegCommandsMu.RUnlock()

		if completed {
			ffmpegCommandsMu.RLock()
			result := map[string]interface{}{
				"success": cmd.Success,
				"output":  cmd.Output,
			}
			if cmd.Error != "" {
				result["error"] = cmd.Error
			}
			ffmpegCommandsMu.RUnlock()

			// Cleanup
			ClearFFmpegCommand(cmdID)
			return r.vm.ToValue(result)
		}

		if time.Since(start) > timeout {
			ClearFFmpegCommand(cmdID)
			return r.vm.ToValue(map[string]interface{}{
				"success": false,
				"error":   "FFmpeg command timed out",
			})
		}

		time.Sleep(100 * time.Millisecond)
	}
}

// ffmpegGetInfo gets audio file information using FFprobe
func (r *ExtensionRuntime) ffmpegGetInfo(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 1 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "file path is required",
		})
	}

	filePath := call.Arguments[0].String()

	// Use Go's built-in audio quality function
	quality, err := GetAudioQuality(filePath)
	if err != nil {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
	}

	return r.vm.ToValue(map[string]interface{}{
		"success":       true,
		"bit_depth":     quality.BitDepth,
		"sample_rate":   quality.SampleRate,
		"total_samples": quality.TotalSamples,
		"duration":      float64(quality.TotalSamples) / float64(quality.SampleRate),
	})
}

// ffmpegConvert is a helper for common conversion operations
func (r *ExtensionRuntime) ffmpegConvert(call goja.FunctionCall) goja.Value {
	if len(call.Arguments) < 2 {
		return r.vm.ToValue(map[string]interface{}{
			"success": false,
			"error":   "input and output paths are required",
		})
	}

	inputPath := call.Arguments[0].String()
	outputPath := call.Arguments[1].String()

	// Get options if provided
	options := map[string]interface{}{}
	if len(call.Arguments) > 2 && !goja.IsUndefined(call.Arguments[2]) && !goja.IsNull(call.Arguments[2]) {
		if opts, ok := call.Arguments[2].Export().(map[string]interface{}); ok {
			options = opts
		}
	}

	// Build FFmpeg command
	var cmdParts []string
	cmdParts = append(cmdParts, "-i", fmt.Sprintf("%q", inputPath))

	// Audio codec
	if codec, ok := options["codec"].(string); ok {
		cmdParts = append(cmdParts, "-c:a", codec)
	}

	// Bitrate
	if bitrate, ok := options["bitrate"].(string); ok {
		cmdParts = append(cmdParts, "-b:a", bitrate)
	}

	// Sample rate
	if sampleRate, ok := options["sample_rate"].(float64); ok {
		cmdParts = append(cmdParts, "-ar", fmt.Sprintf("%d", int(sampleRate)))
	}

	// Channels
	if channels, ok := options["channels"].(float64); ok {
		cmdParts = append(cmdParts, "-ac", fmt.Sprintf("%d", int(channels)))
	}

	// Overwrite output
	cmdParts = append(cmdParts, "-y", fmt.Sprintf("%q", outputPath))

	command := strings.Join(cmdParts, " ")

	// Execute via ffmpegExecute
	execCall := goja.FunctionCall{
		Arguments: []goja.Value{r.vm.ToValue(command)},
	}
	return r.ffmpegExecute(execCall)
}
