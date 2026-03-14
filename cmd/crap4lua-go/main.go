package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/billyq/crap4lua/internal/analyzer"
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
	requestJSON := flags.String("request-json", "", "Path to request JSON")
	responseJSON := flags.String("response-json", "", "Path to response JSON")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *requestJSON == "" || *responseJSON == "" {
		return fmt.Errorf("report requires --request-json and --response-json")
	}
	request, err := ipc.ReadJSON[ipc.ReportRequest](*requestJSON)
	if err != nil {
		return err
	}
	response, err := analyzer.BuildReport(request)
	if err != nil {
		return err
	}
	analyzer.PrintSummary(response, request.Top)
	if err := ipc.WriteJSON(*responseJSON, response); err != nil {
		return err
	}
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
	fmt.Println("  crap4lua-go viewer --in-json <file> --out-dir <dir> [--open]")
}
