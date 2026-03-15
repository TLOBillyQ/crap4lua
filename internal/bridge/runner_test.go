package bridge

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestCollectLoadsBridgeModule(t *testing.T) {
	if _, err := exec.LookPath("lua"); err != nil {
		t.Skip("lua not available")
	}

	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	repoRoot := filepath.Clean(filepath.Join(cwd, "..", ".."))
	runner := New("lua", repoRoot)
	resp, err := runner.Collect(RunCollectOptions{
		ConfigPath: filepath.Join(repoRoot, "tests", "fixtures", "basic_project", "crap4lua.config.lua"),
		RepoRoot:   repoRoot,
	})
	if err != nil {
		t.Fatal(err)
	}
	if resp.ProjectName != "Fixture App" {
		t.Fatalf("expected project name, got %q", resp.ProjectName)
	}
	if len(resp.SourceRoots) != 1 || resp.SourceRoots[0] != "src" {
		t.Fatalf("unexpected source roots: %+v", resp.SourceRoots)
	}
	if resp.CoverageResult.LineHits["src/sample.lua"] == nil {
		t.Fatalf("expected collected line hits")
	}
}

func TestCollectReturnsLuaNotFound(t *testing.T) {
	runner := New("lua-does-not-exist-for-crap4lua", ".")
	_, err := runner.Collect(RunCollectOptions{ConfigPath: "fixture.lua"})
	if err == nil || !strings.Contains(err.Error(), ErrLuaNotFound.Error()) {
		t.Fatalf("expected lua not found error, got %v", err)
	}
}

func TestCollectRejectsEmptyOutput(t *testing.T) {
	luaBin := writeFakeLua(t, "#!/bin/sh\nexit 0\n")
	runner := New(luaBin, ".")
	_, err := runner.Collect(RunCollectOptions{ConfigPath: "fixture.lua"})
	if err == nil || !strings.Contains(err.Error(), "empty output") {
		t.Fatalf("expected empty output error, got %v", err)
	}
}

func TestCollectRejectsInvalidJSONOutput(t *testing.T) {
	luaBin := writeFakeLua(t, "#!/bin/sh\nprintf 'not-json\\n'\n")
	runner := New(luaBin, ".")
	_, err := runner.Collect(RunCollectOptions{ConfigPath: "fixture.lua"})
	if err == nil || !strings.Contains(err.Error(), ErrBridgeJSONInvalid.Error()) {
		t.Fatalf("expected invalid json error, got %v", err)
	}
}

func TestBuildCollectChunkIncludesModuleCallAndOptions(t *testing.T) {
	chunk := buildCollectChunk("/repo/root", RunCollectOptions{
		ConfigPath:  "examples/basic/crap4lua.config.lua",
		Lanes:       []string{"unit", "ci"},
		Mode:        "full",
		ProjectRoot: "sub/project",
	})

	for _, needle := range []string{
		`package.path = "/repo/root/lib/?.lua"`,
		`"/repo/root/lib/?/?.lua"`,
		`require("crap4lua.bridge")`,
		`require("crap4lua._internal.json_writer")`,
		`config = "examples/basic/crap4lua.config.lua"`,
		`lanes = {"unit", "ci"}`,
		`mode = "full"`,
		`project_root = "sub/project"`,
	} {
		if !strings.Contains(chunk, needle) {
			t.Fatalf("expected chunk to include %q, got:\n%s", needle, chunk)
		}
	}
}

func writeFakeLua(t *testing.T, script string) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("fake lua helper is unix-only")
	}
	path := filepath.Join(t.TempDir(), "lua")
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}
