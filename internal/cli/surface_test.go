package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRockspecExportsOnlyBridgeRuntime(t *testing.T) {
	content, err := os.ReadFile(filepath.Join("..", "..", "crap4lua-dev-1.rockspec"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(content)

	for _, required := range []string{
		"crap4lua.bridge",
		"crap4lua.config",
		"crap4lua.coverage",
		"crap4lua._internal.common",
		"crap4lua._internal.json_writer",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("expected rockspec to include %q", required)
		}
	}

	for _, banned := range []string{
		"crap4lua.cli",
		"crap4lua.common",
		"crap4lua.engine",
		"crap4lua.json_reader",
		"crap4lua.json_writer",
		"crap4lua.report",
		"crap4lua.viewer",
	} {
		if strings.Contains(text, banned) {
			t.Fatalf("expected rockspec to exclude %q", banned)
		}
	}
}

func TestRepoDoesNotReferenceRemovedSurface(t *testing.T) {
	banned := []string{
		"crap4lua" + "-go",
		"bin/crap4lua" + ".lua",
		"require(\"crap4lua.report\")",
		"require(\"crap4lua.viewer\")",
		"require(\"crap4lua.engine\")",
		"require(\"crap4lua.cli\")",
		"require(\"crap4lua\")",
	}

	err := filepath.Walk("../..", func(path string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if info.IsDir() {
			name := info.Name()
			if name == ".git" || name == "tmp" || name == "bin" {
				return filepath.SkipDir
			}
			return nil
		}
		name := info.Name()
		if strings.HasSuffix(name, "_test.go") {
			return nil
		}
		allowed := name == "README.md" || name == "Makefile" || name == ".gitignore" || strings.HasSuffix(name, ".md") || strings.HasSuffix(name, ".go") || strings.HasSuffix(name, ".lua") || strings.HasSuffix(name, ".rockspec")
		if !allowed {
			return nil
		}
		content, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		text := string(content)
		for _, needle := range banned {
			if strings.Contains(text, needle) {
				t.Fatalf("found removed surface %q in %s", needle, path)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
