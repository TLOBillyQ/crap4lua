package bridge

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/billyq/crap4lua/internal/ipc"
)

var (
	ErrLuaNotFound        = errors.New("lua runtime not found")
	ErrBridgeInvokeFailed = errors.New("lua bridge invocation failed")
	ErrBridgeJSONInvalid  = errors.New("invalid bridge json output")
)

// RunCollectOptions controls how the Lua bridge collect command is invoked.
type RunCollectOptions struct {
	// ConfigPath points to crap4lua.config.lua
	ConfigPath string

	// Lanes overrides coverage lanes. Empty means use config defaults.
	Lanes []string

	// Mode overrides coverage mode.
	Mode string

	// ProjectRoot overrides project root used by bridge.
	ProjectRoot string

	// LuaBinary optionally sets lua executable path/name (e.g. "lua", "lua5.4").
	LuaBinary string

	// RepoRoot optionally sets repository root containing the Lua bridge modules.
	// If empty, current working directory is used.
	RepoRoot string
}

// Runner executes Lua bridge commands.
type Runner struct {
	LuaBinary string
	RepoRoot  string
}

// New creates a Runner with optional defaults.
func New(luaBinary, repoRoot string) *Runner {
	return &Runner{
		LuaBinary: luaBinary,
		RepoRoot:  repoRoot,
	}
}

// Collect loads the Lua bridge modules directly and parses the JSON output into
// BridgeCollectResponse.
func (r *Runner) Collect(opts RunCollectOptions) (ipc.BridgeCollectResponse, error) {
	var zero ipc.BridgeCollectResponse

	if strings.TrimSpace(opts.ConfigPath) == "" {
		return zero, fmt.Errorf("bridge collect requires config path")
	}

	luaBin := firstNonEmpty(opts.LuaBinary, r.LuaBinary, "lua")
	if _, err := exec.LookPath(luaBin); err != nil {
		return zero, fmt.Errorf("%w: %s", ErrLuaNotFound, luaBin)
	}

	repoRoot := firstNonEmpty(opts.RepoRoot, r.RepoRoot)
	if repoRoot == "" {
		repoRoot = "."
	}
	repoRoot, _ = filepath.Abs(repoRoot)

	cmd := exec.Command(luaBin, "-e", buildCollectChunk(repoRoot, opts))
	cmd.Dir = repoRoot

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = strings.TrimSpace(stdout.String())
		}
		if msg == "" {
			msg = err.Error()
		}
		return zero, fmt.Errorf("%w: %s", ErrBridgeInvokeFailed, msg)
	}

	payload := pickJSON(stdout.String())
	if strings.TrimSpace(payload) == "" {
		return zero, fmt.Errorf("%w: empty output", ErrBridgeJSONInvalid)
	}

	var resp ipc.BridgeCollectResponse
	if err := json.Unmarshal([]byte(payload), &resp); err != nil {
		return zero, fmt.Errorf("%w: %v", ErrBridgeJSONInvalid, err)
	}
	if err := validateResponse(resp); err != nil {
		return zero, err
	}
	return resp, nil
}

func ToReportRequest(resp ipc.BridgeCollectResponse, top int, strictTests bool) ipc.ReportRequest {
	if top < 1 {
		top = 20
	}
	return ipc.ReportRequest{
		ProjectRoot:    resp.ProjectRoot,
		ProjectName:    resp.ProjectName,
		SourceRoots:    append([]string(nil), resp.SourceRoots...),
		CoverageResult: resp.CoverageResult,
		Top:            top,
		StrictTests:    strictTests,
	}
}

func validateResponse(resp ipc.BridgeCollectResponse) error {
	if strings.TrimSpace(resp.ProjectRoot) == "" {
		return fmt.Errorf("%w: missing project_root", ErrBridgeJSONInvalid)
	}
	if len(resp.SourceRoots) == 0 {
		return fmt.Errorf("%w: missing source_roots", ErrBridgeJSONInvalid)
	}
	if resp.CoverageResult.LineHits == nil {
		resp.CoverageResult.LineHits = ipc.LineHits{}
	}
	if resp.CoverageResult.Lanes == nil {
		resp.CoverageResult.Lanes = []ipc.LaneResult{}
	}
	return nil
}

// pickJSON extracts the most likely JSON body from mixed stdout text.
// If output already looks like plain JSON, it is returned as-is.
// Otherwise, it returns the substring from the first '{' to the last '}'.
func pickJSON(output string) string {
	trimmed := strings.TrimSpace(output)
	if trimmed == "" {
		return ""
	}
	if strings.HasPrefix(trimmed, "{") && strings.HasSuffix(trimmed, "}") {
		return trimmed
	}
	start := strings.Index(trimmed, "{")
	end := strings.LastIndex(trimmed, "}")
	if start >= 0 && end > start {
		return strings.TrimSpace(trimmed[start : end+1])
	}
	return ""
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func buildCollectChunk(repoRoot string, opts RunCollectOptions) string {
	paths := []string{
		filepath.ToSlash(filepath.Join(repoRoot, "lib", "?.lua")),
		filepath.ToSlash(filepath.Join(repoRoot, "lib", "?", "?.lua")),
	}

	var chunk strings.Builder
	fmt.Fprintf(&chunk, "package.path = %s .. ';' .. %s .. ';' .. package.path\n", luaString(paths[0]), luaString(paths[1]))
	chunk.WriteString("local bridge = require(\"crap4lua.bridge\")\n")
	chunk.WriteString("local json_writer = require(\"crap4lua._internal.json_writer\")\n")
	chunk.WriteString("local result, err = bridge.collect({\n")
	fmt.Fprintf(&chunk, "  config = %s,\n", luaString(opts.ConfigPath))
	if len(opts.Lanes) > 0 {
		chunk.WriteString("  lanes = {")
		first := true
		for _, lane := range opts.Lanes {
			if strings.TrimSpace(lane) == "" {
				continue
			}
			if !first {
				chunk.WriteString(", ")
			}
			chunk.WriteString(luaString(lane))
			first = false
		}
		chunk.WriteString("},\n")
	}
	if strings.TrimSpace(opts.Mode) != "" {
		fmt.Fprintf(&chunk, "  mode = %s,\n", luaString(opts.Mode))
	}
	if strings.TrimSpace(opts.ProjectRoot) != "" {
		fmt.Fprintf(&chunk, "  project_root = %s,\n", luaString(opts.ProjectRoot))
	}
	chunk.WriteString("})\n")
	chunk.WriteString("if not result then\n")
	chunk.WriteString("  io.stderr:write(tostring(err), \"\\n\")\n")
	chunk.WriteString("  os.exit(1)\n")
	chunk.WriteString("end\n")
	chunk.WriteString("io.write(json_writer.encode(result))\n")
	chunk.WriteString("io.write(\"\\n\")\n")
	return chunk.String()
}

func luaString(value string) string {
	replacer := strings.NewReplacer(
		"\\", "\\\\",
		"\"", "\\\"",
		"\n", "\\n",
		"\r", "\\r",
		"\t", "\\t",
	)
	return "\"" + replacer.Replace(value) + "\""
}
