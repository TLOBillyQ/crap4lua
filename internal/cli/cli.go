package cli

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/billyq/crap4lua/internal/app"
)

type runner interface {
	RunReport(app.ReportOptions) (int, error)
	RunCollect(app.CollectOptions) error
	RunViewer(app.ViewerOptions) error
}

type dependencies struct {
	stdout io.Writer
	stderr io.Writer
	runner runner
}

func Main(args []string) int {
	if len(args) == 0 {
		args = []string{"crap4lua"}
	}
	return run(args, dependencies{
		stdout: os.Stdout,
		stderr: os.Stderr,
		runner: app.Runner{},
	})
}

func run(args []string, deps dependencies) int {
	program := commandName(args)
	if deps.stdout == nil {
		deps.stdout = io.Discard
	}
	if deps.stderr == nil {
		deps.stderr = io.Discard
	}
	if deps.runner == nil {
		deps.runner = app.Runner{}
	}

	if len(args) < 2 {
		usage(deps.stderr, program)
		return 1
	}

	switch args[1] {
	case "help", "--help", "-h":
		usage(deps.stdout, program)
		return 0
	case "report":
		return runReport(args[2:], deps)
	case "collect":
		return runCollect(args[2:], deps)
	case "viewer":
		return runViewer(args[2:], deps)
	default:
		fmt.Fprintf(deps.stderr, "unknown command: %s\n", args[1])
		usage(deps.stderr, program)
		return 1
	}
}

func runReport(args []string, deps dependencies) int {
	flags := flag.NewFlagSet("report", flag.ContinueOnError)
	flags.SetOutput(deps.stderr)

	requestJSON := flags.String("request-json", "", "Path to report request JSON")
	responseJSON := flags.String("response-json", "", "Path to report response JSON")
	configPath := flags.String("config", "", "Path to crap4lua.config.lua")
	mode := flags.String("mode", "", "Coverage mode override")
	projectRoot := flags.String("project-root", "", "Project root override")
	top := flags.Int("top", 20, "Top hotspot count for summary output")
	strictTests := flags.Bool("strict-tests", false, "Return non-zero exit when any lane fails")
	luaBin := flags.String("lua-bin", "", "Lua executable path/name (default: lua)")

	var lanes multiStringFlag
	flags.Var(&lanes, "lane", "Coverage lane override (repeatable)")

	if err := flags.Parse(args); err != nil {
		return 1
	}

	exitCode, err := deps.runner.RunReport(app.ReportOptions{
		RequestJSON:  *requestJSON,
		ResponseJSON: *responseJSON,
		ConfigPath:   *configPath,
		Lanes:        lanes.Values(),
		Mode:         *mode,
		ProjectRoot:  *projectRoot,
		Top:          *top,
		StrictTests:  *strictTests,
		LuaBin:       *luaBin,
	})
	if err != nil {
		fmt.Fprintln(deps.stderr, err)
		return 1
	}
	return exitCode
}

func runCollect(args []string, deps dependencies) int {
	flags := flag.NewFlagSet("collect", flag.ContinueOnError)
	flags.SetOutput(deps.stderr)

	configPath := flags.String("config", "", "Path to crap4lua.config.lua")
	outJSON := flags.String("out", "", "Path to bridge collect output JSON")
	mode := flags.String("mode", "", "Coverage mode override")
	projectRoot := flags.String("project-root", "", "Project root override")
	luaBin := flags.String("lua-bin", "", "Lua executable path/name (default: lua)")

	var lanes multiStringFlag
	flags.Var(&lanes, "lane", "Coverage lane override (repeatable)")

	if err := flags.Parse(args); err != nil {
		return 1
	}
	if err := deps.runner.RunCollect(app.CollectOptions{
		ConfigPath:  *configPath,
		OutJSON:     *outJSON,
		Lanes:       lanes.Values(),
		Mode:        *mode,
		ProjectRoot: *projectRoot,
		LuaBin:      *luaBin,
	}); err != nil {
		fmt.Fprintln(deps.stderr, err)
		return 1
	}
	return 0
}

func runViewer(args []string, deps dependencies) int {
	flags := flag.NewFlagSet("viewer", flag.ContinueOnError)
	flags.SetOutput(deps.stderr)

	inJSON := flags.String("in-json", "", "Path to report JSON")
	outDir := flags.String("out-dir", "", "Output directory")
	open := flags.Bool("open", false, "Open the viewer after writing")

	if err := flags.Parse(args); err != nil {
		return 1
	}
	if err := deps.runner.RunViewer(app.ViewerOptions{
		InJSON: *inJSON,
		OutDir: *outDir,
		Open:   *open,
	}); err != nil {
		fmt.Fprintln(deps.stderr, err)
		return 1
	}
	return 0
}

func usage(w io.Writer, program string) {
	fmt.Fprintf(w, "Usage:\n")
	fmt.Fprintf(w, "  %s report --request-json <file> --response-json <file>\n", program)
	fmt.Fprintf(w, "  %s report --config <file> [--lane <name>] [--mode <name>] [--top <n>] [--strict-tests] [--project-root <dir>] [--response-json <file>] [--lua-bin <path>]\n", program)
	fmt.Fprintf(w, "  %s collect --config <file> --out <json> [--lane <name>] [--mode <name>] [--project-root <dir>] [--lua-bin <path>]\n", program)
	fmt.Fprintf(w, "  %s viewer --in-json <file> --out-dir <dir> [--open]\n", program)
}

func commandName(args []string) string {
	if len(args) == 0 || strings.TrimSpace(args[0]) == "" {
		return "crap4lua"
	}
	return filepath.Base(args[0])
}

type multiStringFlag struct {
	values []string
}

func (m *multiStringFlag) String() string {
	return fmt.Sprintf("%v", m.values)
}

func (m *multiStringFlag) Set(value string) error {
	m.values = append(m.values, value)
	return nil
}

func (m *multiStringFlag) Values() []string {
	return append([]string(nil), m.values...)
}
