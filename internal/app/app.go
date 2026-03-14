package app

import (
	"fmt"
	"os"

	"github.com/billyq/crap4lua/internal/analyzer"
	"github.com/billyq/crap4lua/internal/bridge"
	"github.com/billyq/crap4lua/internal/ipc"
	"github.com/billyq/crap4lua/internal/viewer"
)

type ReportOptions struct {
	RequestJSON  string
	ResponseJSON string
	ConfigPath   string
	Lanes        []string
	Mode         string
	ProjectRoot  string
	Top          int
	StrictTests  bool
	LuaBin       string
	RepoRoot     string
}

type CollectOptions struct {
	ConfigPath  string
	OutJSON     string
	Lanes       []string
	Mode        string
	ProjectRoot string
	LuaBin      string
	RepoRoot    string
}

type ViewerOptions struct {
	InJSON string
	OutDir string
	Open   bool
}

type Runner struct{}

func (Runner) RunReport(opts ReportOptions) (int, error) {
	return RunReport(opts)
}

func (Runner) RunCollect(opts CollectOptions) error {
	return RunCollect(opts)
}

func (Runner) RunViewer(opts ViewerOptions) error {
	return RunViewer(opts)
}

func RunReport(opts ReportOptions) (int, error) {
	configMode := opts.ConfigPath != ""
	legacyMode := opts.RequestJSON != ""

	if legacyMode && configMode {
		return 1, fmt.Errorf("report accepts either --request-json/--response-json or --config mode, not both")
	}

	if legacyMode {
		if opts.ResponseJSON == "" {
			return 1, fmt.Errorf("report requires both --request-json and --response-json")
		}
		req, err := ipc.ReadJSON[ipc.ReportRequest](opts.RequestJSON)
		if err != nil {
			return 1, err
		}
		resp, err := analyzer.BuildReport(req)
		if err != nil {
			return 1, err
		}
		analyzer.PrintSummary(resp, req.Top)
		if err := ipc.WriteJSON(opts.ResponseJSON, resp); err != nil {
			return 1, err
		}
		return resp.ExitCode, nil
	}

	if !configMode {
		return 1, fmt.Errorf("report requires either --config <file> or --request-json/--response-json")
	}

	repoRoot := opts.RepoRoot
	if repoRoot == "" {
		var err error
		repoRoot, err = os.Getwd()
		if err != nil {
			return 1, err
		}
	}

	runner := bridge.New(opts.LuaBin, repoRoot)
	bridgeResp, err := runner.Collect(bridge.RunCollectOptions{
		ConfigPath:  opts.ConfigPath,
		Lanes:       opts.Lanes,
		Mode:        opts.Mode,
		ProjectRoot: opts.ProjectRoot,
		LuaBinary:   opts.LuaBin,
		RepoRoot:    repoRoot,
	})
	if err != nil {
		return 1, err
	}

	req := bridge.ToReportRequest(bridgeResp, opts.Top, opts.StrictTests)
	resp, err := analyzer.BuildReport(req)
	if err != nil {
		return 1, err
	}
	analyzer.PrintSummary(resp, req.Top)
	if opts.ResponseJSON != "" {
		if err := ipc.WriteJSON(opts.ResponseJSON, resp); err != nil {
			return 1, err
		}
	}
	return resp.ExitCode, nil
}

func RunCollect(opts CollectOptions) error {
	if opts.ConfigPath == "" {
		return fmt.Errorf("collect requires --config <file>")
	}
	if opts.OutJSON == "" {
		return fmt.Errorf("collect requires --out <json>")
	}

	repoRoot := opts.RepoRoot
	if repoRoot == "" {
		var err error
		repoRoot, err = os.Getwd()
		if err != nil {
			return err
		}
	}

	runner := bridge.New(opts.LuaBin, repoRoot)
	resp, err := runner.Collect(bridge.RunCollectOptions{
		ConfigPath:  opts.ConfigPath,
		Lanes:       opts.Lanes,
		Mode:        opts.Mode,
		ProjectRoot: opts.ProjectRoot,
		LuaBinary:   opts.LuaBin,
		RepoRoot:    repoRoot,
	})
	if err != nil {
		return err
	}
	if err := ipc.WriteJSON(opts.OutJSON, resp); err != nil {
		return err
	}
	fmt.Printf("[crap] collect_json=%s\n", opts.OutJSON)
	return nil
}

func RunViewer(opts ViewerOptions) error {
	if opts.InJSON == "" || opts.OutDir == "" {
		return fmt.Errorf("viewer requires --in-json and --out-dir")
	}
	return viewer.WriteBundle(opts.InJSON, opts.OutDir, opts.Open)
}
