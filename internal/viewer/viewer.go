package viewer

import (
	"embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"github.com/billyq/crap4lua/internal/ipc"
)

//go:embed assets/viewer/*
var embeddedAssets embed.FS

func WriteBundle(inJSON string, outDir string, open bool) error {
	report, err := ipc.ReadJSON[ipc.ReportResponse](inJSON)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}
	if err := writeAsset("assets/viewer/index.html", filepath.Join(outDir, "index.html")); err != nil {
		return err
	}
	if err := writeAsset("assets/viewer/script.js", filepath.Join(outDir, "script.js")); err != nil {
		return err
	}
	if err := writeAsset("assets/viewer/styles.css", filepath.Join(outDir, "styles.css")); err != nil {
		return err
	}
	if err := ipc.WriteJSON(filepath.Join(outDir, "crap_report.json"), report); err != nil {
		return err
	}
	content, err := os.ReadFile(inJSON)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(outDir, "crap_report_data.js"), append([]byte("window.CRAP_REPORT_DATA = "), append(content, []byte(";\n")...)...), 0o644); err != nil {
		return err
	}
	indexPath, err := filepath.Abs(filepath.Join(outDir, "index.html"))
	if err != nil {
		return err
	}
	fmt.Printf("[crap] viewer_index=%s\n", normalizePath(indexPath))
	if open {
		if err := openPath(indexPath); err != nil {
			return err
		}
		fmt.Printf("[crap] viewer_opened=%s\n", normalizePath(indexPath))
	}
	fmt.Printf("[crap] viewer_ok=%s\n", normalizePath(outDir))
	return nil
}

func writeAsset(assetPath string, outPath string) error {
	content, err := embeddedAssets.ReadFile(assetPath)
	if err != nil {
		return err
	}
	return os.WriteFile(outPath, content, 0o644)
}

func openPath(path string) error {
	var command *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		command = exec.Command("cmd", "/c", "start", "", path)
	case "darwin":
		command = exec.Command("open", path)
	default:
		command = exec.Command("xdg-open", path)
	}
	return command.Start()
}

func normalizePath(path string) string {
	return filepath.ToSlash(path)
}
