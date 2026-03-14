package analyzer

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/billyq/crap4lua/internal/ipc"
)

func TestBuildReportComputesMetrics(t *testing.T) {
	if _, err := exec.LookPath("luac"); err != nil {
		t.Skip("luac not available")
	}
	root := t.TempDir()
	sourceDir := filepath.Join(root, "src")
	if err := os.MkdirAll(sourceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	content := "local function alpha(flag)\n  if flag then\n    return 1\n  end\n  return 0\nend\n\nlocal sample = {}\nfunction sample.beta(n)\n  local total = 0\n  for i = 1, n do\n    total = total + i\n  end\n  return total\nend\n\nreturn sample\n"
	if err := os.WriteFile(filepath.Join(sourceDir, "sample.lua"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	resp, err := BuildReport(ipc.ReportRequest{
		ProjectRoot: root,
		ProjectName: "Synthetic App",
		SourceRoots: []string{"src"},
		Top:         3,
		CoverageResult: ipc.CoverageResult{
			LineHits: map[string]map[string]bool{
				"src/sample.lua": {
					"1":  true,
					"2":  true,
					"3":  true,
					"9":  true,
					"10": true,
					"11": true,
					"12": true,
				},
			},
			Lanes: []ipc.LaneResult{{Lane: "unit", Mode: "synthetic", Total: 1}},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if resp.Metadata.Engine != "go" {
		t.Fatalf("expected go engine, got %q", resp.Metadata.Engine)
	}
	if resp.Metadata.SchemaVersion != 3 {
		t.Fatalf("expected schema version 3, got %d", resp.Metadata.SchemaVersion)
	}
	if len(resp.Functions) != 2 {
		t.Fatalf("expected 2 functions, got %d", len(resp.Functions))
	}
	if resp.Functions[0].CRAP < resp.Functions[1].CRAP {
		t.Fatalf("expected functions sorted by CRAP descending")
	}
}

func TestCacheSaveAndLoad(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cache.json")
	input := cacheFile{
		Version: cacheVersion,
		Entries: map[string]cacheEntry{
			"src/sample.lua": {
				SourceHash: "abc",
				Functions:  []functionInfo{{Name: "alpha", ExecutableLines: []int{1, 2}, DecisionLines: []int{1}}},
			},
		},
	}
	if err := saveCache(path, input); err != nil {
		t.Fatal(err)
	}
	loaded, err := loadCache(path)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.Entries["src/sample.lua"].SourceHash != "abc" {
		t.Fatalf("expected cache round-trip")
	}
}

func TestBuildReportWritesCacheFile(t *testing.T) {
	if _, err := exec.LookPath("luac"); err != nil {
		t.Skip("luac not available")
	}
	root := t.TempDir()
	sourceDir := filepath.Join(root, "src")
	if err := os.MkdirAll(sourceDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sourceDir, "sample.lua"), []byte("local function alpha() return 1 end\nreturn { alpha = alpha }\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := BuildReport(ipc.ReportRequest{
		ProjectRoot: root,
		SourceRoots: []string{"src"},
		CoverageResult: ipc.CoverageResult{
			LineHits: map[string]map[string]bool{},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(cachePathForProject(normalizePath(root))); err != nil {
		t.Fatalf("expected cache file to exist: %v", err)
	}
}
