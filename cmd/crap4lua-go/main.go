package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/billyq/crap4lua/internal/analyzer"
	"github.com/billyq/crap4lua/internal/bridge"
	"github.com/billyq/crap4lua/internal/ipc"
	"github.com/billyq/crap4lua/internal/viewer"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "report":
		if err := runReport(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "viewer":
		if err := runViewer(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "collect":
		if err := runCollect(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "--help", "-h", "help":
		usage()
	default:
		usage()
		os.Exit(1)
	}
}

func runReport(args []string) error {
	flags := flag.NewFlagSet("report", flag.ContinueOnError)
	flags.SetOutput(os.Stdout)

	// legacy low-level mode
	requestJSON := flags.String("request-json", "", "Path to report request JSON")
	responseJSON := flags.String("response-json", "", "Path to report response JSON")

	// config-driven mode
	configPath := flags.String("config", "", "Path to crap4lua.config.lua")
	mode := flags.String("mode", "", "Coverage mode override")
	projectRoot := flags.String("project-root", "", "Project root override")
	top := flags.Int("top", 20, "Top hotspot count for summary output")
	strictTests := flags.Bool("strict-tests", false, "Return non-zero exit when any lane fails")
	luaBin := flags.String("lua-bin", "", "Lua executable path/name (default: lua)")

	var lanes multiStringFlag
	flags.Var(&lanes, "lane", "Coverage lane override (repeatable)")

	if err := flags.Parse(args); err != nil {
		return err
	}

	configMode := *configPath != ""
	legacyMode := *requestJSON != ""

	if legacyMode && configMode {
		return fmt.Errorf("report accepts either --request-json/--response-json or --config mode, not both")
	}

	// Keep existing behavior for low-level mode.
	if legacyMode {
		if *responseJSON == "" {
			return fmt.Errorf("report requires both --request-json and --response-json")
		}
		req, err := ipc.ReadJSON[ipc.ReportRequest](*requestJSON)
		if err != nil {
			return err
		}
		resp, err := analyzer.BuildReport(req)
		if err != nil {
			return err
		}
		analyzer.PrintSummary(resp, req.Top)
		if err := ipc.WriteJSON(*responseJSON, resp); err != nil {
			return err
		}
		return exitByCode(resp.ExitCode)
	}

	// New config-driven mode.
	if !configMode {
		return fmt.Errorf("report requires either --config <file> or --request-json/--response-json")
	}

	repoRoot, err := os.Getwd()
	if err != nil {
		return err
	}

	runner := bridge.New(*luaBin, repoRoot)
	bridgeResp, err := runner.Collect(bridge.RunCollectOptions{
		ConfigPath:  *configPath,
		Lanes:       lanes.Values(),
		Mode:        *mode,
		ProjectRoot: *projectRoot,
		LuaBinary:   *luaBin,
		RepoRoot:    repoRoot,
	})
	if err != nil {
		return err
	}

	req := bridge.ToReportRequest(bridgeResp, *top, *strictTests)
	resp, err := analyzer.BuildReport(req)
	if err != nil {
		return err
	}
	analyzer.PrintSummary(resp, req.Top)

	// in config-driven mode, response path is optional
	if *responseJSON != "" {
		if err := ipc.WriteJSON(*responseJSON, resp); err != nil {
			return err
		}
	}

	return exitByCode(resp.ExitCode)
}

func runCollect(args []string) error {
	flags := flag.NewFlagSet("collect", flag.ContinueOnError)
	flags.SetOutput(os.Stdout)

	configPath := flags.String("config", "", "Path to crap4lua.config.lua")
	outJSON := flags.String("out", "", "Path to bridge collect output JSON")
	mode := flags.String("mode", "", "Coverage mode override")
	projectRoot := flags.String("project-root", "", "Project root override")
	luaBin := flags.String("lua-bin", "", "Lua executable path/name (default: lua)")

	var lanes multiStringFlag
	flags.Var(&lanes, "lane", "Coverage lane override (repeatable)")

	if err := flags.Parse(args); err != nil {
		return err
	}
	if *configPath == "" {
		return fmt.Errorf("collect requires --config <file>")
	}

	repoRoot, err := os.Getwd()
	if err != nil {
		return err
	}

	runner := bridge.New(*luaBin, repoRoot)
	resp, err := runner.Collect(bridge.RunCollectOptions{
		ConfigPath:  *configPath,
		Lanes:       lanes.Values(),
		Mode:        *mode,
		ProjectRoot: *projectRoot,
		LuaBinary:   *luaBin,
		RepoRoot:    repoRoot,
	})
	if err != nil {
		return err
	}

	if *outJSON == "" {
		return fmt.Errorf("collect requires --out <json>")
	}
	if err := ipc.WriteJSON(*outJSON, resp); err != nil {
		return err
	}
	fmt.Printf("[crap] collect_json=%s\n", *outJSON)
	return nil
}

func runViewer(args []string) error {
	flags := flag.NewFlagSet("viewer", flag.ContinueOnError)
	flags.SetOutput(os.Stdout)

	inJSON := flags.String("in-json", "", "Path to report JSON")
	outDir := flags.String("out-dir", "", "Output directory")
	open := flags.Bool("open", false, "Open the viewer after writing")

	if err := flags.Parse(args); err != nil {
		return err
	}
	if *inJSON == "" || *outDir == "" {
		return fmt.Errorf("viewer requires --in-json and --out-dir")
	}
	return viewer.WriteBundle(*inJSON, *outDir, *open)
}

func usage() {
	fmt.Println("Usage:")
	fmt.Println("  crap4lua-go report --request-json <file> --response-json <file>")
	fmt.Println("  crap4lua-go report --config <file> [--lane <name>] [--mode <name>] [--top <n>] [--strict-tests] [--project-root <dir>] [--response-json <file>]")
	fmt.Println("  crap4lua-go collect --config <file> --out <json> [--lane <name>] [--mode <name>] [--project-root <dir>]")
	fmt.Println("  crap4lua-go viewer --in-json <file> --out-dir <dir> [--open]")
}

func exitByCode(code int) error {
	if code != 0 {
		os.Exit(code)
	}
	return nil
}

type multiStringFlag struct {
	values []string
}

func (m *multiStringFlag) String() string {
	return fmt.Sprintf("%v", m.values)
}

func (m *multiStringFlag) Set(value string) error {
	if value != "" {
		m.values = append(m.values, value)
	}
	return nil
}

func (m *multiStringFlag) Values() []string {
	out := make([]string, len(m.values))
	copy(out, m.values)
	return out
}
