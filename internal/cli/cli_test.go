package cli

import (
	"bytes"
	"errors"
	"strings"
	"testing"

	"github.com/billyq/crap4lua/internal/app"
)

type stubRunner struct {
	reportOpts    app.ReportOptions
	collectOpts   app.CollectOptions
	viewerOpts    app.ViewerOptions
	reportExit    int
	reportErr     error
	collectErr    error
	viewerErr     error
	reportCalled  bool
	collectCalled bool
	viewerCalled  bool
}

func (s *stubRunner) RunReport(opts app.ReportOptions) (int, error) {
	s.reportCalled = true
	s.reportOpts = opts
	return s.reportExit, s.reportErr
}

func (s *stubRunner) RunCollect(opts app.CollectOptions) error {
	s.collectCalled = true
	s.collectOpts = opts
	return s.collectErr
}

func (s *stubRunner) RunViewer(opts app.ViewerOptions) error {
	s.viewerCalled = true
	s.viewerOpts = opts
	return s.viewerErr
}

func TestRunPrintsHelp(t *testing.T) {
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	exitCode := run([]string{"/tmp/bin/crap4lua", "help"}, dependencies{
		stdout: &stdout,
		stderr: &stderr,
		runner: &stubRunner{},
	})

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !strings.Contains(stdout.String(), "crap4lua report") {
		t.Fatalf("expected help output, got %q", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Fatalf("expected empty stderr, got %q", stderr.String())
	}
}

func TestRunDispatchesReport(t *testing.T) {
	stub := &stubRunner{reportExit: 7}
	var stderr bytes.Buffer

	exitCode := run([]string{
		"crap4lua", "report",
		"--config", "fixture.lua",
		"--lane", "unit",
		"--mode", "ci",
		"--top", "5",
		"--strict-tests",
		"--project-root", "/tmp/project",
		"--response-json", "out.json",
		"--lua-bin", "lua5.4",
	}, dependencies{stderr: &stderr, runner: stub})

	if exitCode != 7 {
		t.Fatalf("expected runner exit code, got %d", exitCode)
	}
	if !stub.reportCalled {
		t.Fatal("expected report runner to be called")
	}
	if stub.reportOpts.ConfigPath != "fixture.lua" || stub.reportOpts.Mode != "ci" {
		t.Fatalf("unexpected report opts: %+v", stub.reportOpts)
	}
	if len(stub.reportOpts.Lanes) != 1 || stub.reportOpts.Lanes[0] != "unit" {
		t.Fatalf("unexpected report lanes: %+v", stub.reportOpts.Lanes)
	}
	if stub.reportOpts.Top != 5 || !stub.reportOpts.StrictTests {
		t.Fatalf("unexpected top/strict values: %+v", stub.reportOpts)
	}
	if stderr.Len() != 0 {
		t.Fatalf("expected empty stderr, got %q", stderr.String())
	}
}

func TestRunDispatchesCollect(t *testing.T) {
	stub := &stubRunner{}
	var stderr bytes.Buffer

	exitCode := run([]string{
		"crap4lua", "collect",
		"--config", "fixture.lua",
		"--out", "collect.json",
		"--lane", "unit",
		"--mode", "ci",
		"--project-root", "/tmp/project",
		"--lua-bin", "lua5.4",
	}, dependencies{stderr: &stderr, runner: stub})

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !stub.collectCalled {
		t.Fatal("expected collect runner to be called")
	}
	if stub.collectOpts.OutJSON != "collect.json" || stub.collectOpts.ProjectRoot != "/tmp/project" {
		t.Fatalf("unexpected collect opts: %+v", stub.collectOpts)
	}
}

func TestRunDispatchesViewer(t *testing.T) {
	stub := &stubRunner{}
	var stderr bytes.Buffer

	exitCode := run([]string{
		"crap4lua", "viewer",
		"--in-json", "report.json",
		"--out-dir", "viewer",
		"--open",
	}, dependencies{stderr: &stderr, runner: stub})

	if exitCode != 0 {
		t.Fatalf("expected exit code 0, got %d", exitCode)
	}
	if !stub.viewerCalled {
		t.Fatal("expected viewer runner to be called")
	}
	if stub.viewerOpts.InJSON != "report.json" || stub.viewerOpts.OutDir != "viewer" || !stub.viewerOpts.Open {
		t.Fatalf("unexpected viewer opts: %+v", stub.viewerOpts)
	}
}

func TestRunReportsRunnerErrors(t *testing.T) {
	stub := &stubRunner{reportErr: errors.New("boom")}
	var stderr bytes.Buffer

	exitCode := run([]string{"crap4lua", "report", "--config", "fixture.lua"}, dependencies{stderr: &stderr, runner: stub})

	if exitCode != 1 {
		t.Fatalf("expected exit code 1, got %d", exitCode)
	}
	if !strings.Contains(stderr.String(), "boom") {
		t.Fatalf("expected runner error in stderr, got %q", stderr.String())
	}
}

func TestRunRejectsUnknownCommand(t *testing.T) {
	var stderr bytes.Buffer

	exitCode := run([]string{"crap4lua", "unknown"}, dependencies{stderr: &stderr, runner: &stubRunner{}})

	if exitCode != 1 {
		t.Fatalf("expected exit code 1, got %d", exitCode)
	}
	if !strings.Contains(stderr.String(), "unknown command") {
		t.Fatalf("expected unknown command error, got %q", stderr.String())
	}
}
