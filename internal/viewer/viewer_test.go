package viewer

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/billyq/crap4lua/internal/ipc"
)

func TestWriteBundle(t *testing.T) {
	root := t.TempDir()
	inJSON := filepath.Join(root, "report.json")
	outDir := filepath.Join(root, "viewer")
	if err := ipc.WriteJSON(inJSON, ipc.ReportResponse{
		Metadata: ipc.ReportMetadata{ProjectName: "Viewer Fixture", SourceRoots: []string{"src"}},
		Summary:  ipc.ReportSummary{ModuleCount: 1, FunctionCount: 1, TotalCRAP: 1.2},
	}); err != nil {
		t.Fatal(err)
	}
	if err := WriteBundle(inJSON, outDir, false); err != nil {
		t.Fatal(err)
	}
	indexContent, err := os.ReadFile(filepath.Join(outDir, "index.html"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(indexContent), "crap_report_data.js") {
		t.Fatalf("expected viewer asset references")
	}
	dataJS, err := os.ReadFile(filepath.Join(outDir, "crap_report_data.js"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(dataJS), "window.CRAP_REPORT_DATA") {
		t.Fatalf("expected embedded report payload")
	}
}
