package analyzer

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/billyq/crap4lua/internal/ipc"
)

var (
	headerPattern      = regexp.MustCompile(`^([A-Za-z_]+)\s+<(.+):(-?\d+),(-?\d+)>\s+\((\d+)\s+instructions`)
	instructionPattern = regexp.MustCompile(`^\s*\d+\s+\[(-?\d+)\]\s+([A-Z]+)`)
	localNamePattern   = regexp.MustCompile(`^\s*local\s+function\s+([\w_]+)\s*\(`)
	globalNamePattern  = regexp.MustCompile(`^\s*function\s+([\w_%.:]+)\s*\(`)
	assignNamePattern  = regexp.MustCompile(`^\s*([\w_%.]+)\s*=\s*function\s*\(`)
)

var decisionOpcodes = map[string]bool{
	"EQ":       true,
	"LT":       true,
	"LE":       true,
	"TEST":     true,
	"TESTSET":  true,
	"FORLOOP":  true,
	"FORPREP":  true,
	"TFORLOOP": true,
}

type ModuleInfo struct {
	ModuleID           string
	SourcePath         string
	RelativeSourcePath string
	SourceName         string
	SourceText         string
}

type functionInfo struct {
	ID                 string `json:"id"`
	Name               string `json:"name"`
	ModuleID           string `json:"module_id"`
	SourceName         string `json:"source_name"`
	SourcePath         string `json:"source_path"`
	RelativeSourcePath string `json:"relative_source_path"`
	StartLine          int    `json:"start_line"`
	EndLine            int    `json:"end_line"`
	ExecutableLines    []int  `json:"executable_lines"`
	DecisionLines      []int  `json:"decision_lines"`
	Complexity         int    `json:"complexity"`
}

type cacheFile struct {
	Version string                `json:"version"`
	Entries map[string]cacheEntry `json:"entries"`
}

type cacheEntry struct {
	SourceHash string         `json:"source_hash"`
	Functions  []functionInfo `json:"functions"`
}

type instruction struct {
	SourceLine int
	Opcode     string
}

type functionChunk struct {
	Kind         string
	StartLine    int
	EndLine      int
	Instructions []instruction
}

const cacheVersion = "v1"

func BuildReport(req ipc.ReportRequest) (ipc.ReportResponse, error) {
	projectRoot, err := filepath.Abs(req.ProjectRoot)
	if err != nil {
		return ipc.ReportResponse{}, err
	}
	projectRoot = normalizePath(projectRoot)

	modules, err := scanModules(projectRoot, req.SourceRoots)
	if err != nil {
		return ipc.ReportResponse{}, err
	}

	functions, err := analyzeModules(projectRoot, modules)
	if err != nil {
		return ipc.ReportResponse{}, err
	}

	rows := buildFunctions(functions, req.CoverageResult.LineHits)
	moduleRows := buildModules(modules, rows, req.CoverageResult.LineHits)

	totalCRAP := 0.0
	criticalCount := 0
	for _, fn := range rows {
		totalCRAP += fn.CRAP
		if fn.RiskBand == "critical" {
			criticalCount++
		}
	}

	resp := ipc.ReportResponse{
		Metadata: ipc.ReportMetadata{
			Tool:          "crap4lua_report",
			SchemaVersion: 3,
			Engine:        "go",
			ProjectRoot:   projectRoot,
			ProjectName:   defaultProjectName(req.ProjectName, projectRoot),
			SourceRoots:   cloneStrings(req.SourceRoots),
			GeneratedAt:   time.Now().UTC().Format(time.RFC3339),
		},
		Summary: ipc.ReportSummary{
			ModuleCount:           len(moduleRows),
			FunctionCount:         len(rows),
			TotalCRAP:             roundScore(totalCRAP),
			CriticalFunctionCount: criticalCount,
		},
		Lanes:     req.CoverageResult.Lanes,
		Modules:   moduleRows,
		Functions: rows,
		ExitCode:  0,
	}
	if req.StrictTests {
		for _, lane := range resp.Lanes {
			if lane.Failed {
				resp.ExitCode = 1
				break
			}
		}
	}
	return resp, nil
}

func PrintSummary(resp ipc.ReportResponse, top int) {
	fmt.Printf("[crap] analyzed modules=%d functions=%d\n", len(resp.Modules), len(resp.Functions))
	for _, lane := range resp.Lanes {
		status := "passed"
		if lane.Failed {
			status = "failed"
		}
		fmt.Printf("[crap] lane=%s mode=%s status=%s total=%d failures=%d\n", lane.Lane, lane.Mode, status, lane.Total, lane.FailureCount)
	}
	fmt.Println("[crap] top_hotspots")
	if top < 1 {
		top = 1
	}
	if top > len(resp.Functions) {
		top = len(resp.Functions)
	}
	for index := 0; index < top; index++ {
		fn := resp.Functions[index]
		fmt.Printf("  %02d. %s:%s:%d crap=%.2f complexity=%d coverage=%.2f\n", index+1, fn.SourcePath, fn.Name, fn.StartLine, fn.CRAP, fn.Complexity, fn.Coverage)
	}
}

func scanModules(projectRoot string, sourceRoots []string) ([]ModuleInfo, error) {
	var modules []ModuleInfo
	for _, root := range sourceRoots {
		logicalRoot := normalizePath(strings.TrimPrefix(root, "./"))
		filesystemRoot := filepath.Clean(filepath.Join(projectRoot, filepath.FromSlash(root)))
		err := filepath.WalkDir(filesystemRoot, func(path string, d os.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if d.IsDir() {
				return nil
			}
			if filepath.Ext(path) != ".lua" {
				return nil
			}
			normalizedPath := normalizePath(path)
			rel, err := filepath.Rel(filesystemRoot, path)
			if err != nil {
				return err
			}
			rel = normalizePath(rel)
			rel = strings.TrimSuffix(rel, ".lua")
			segments := splitPath(rel)
			if len(segments) > 0 && segments[len(segments)-1] == "init" {
				segments = segments[:len(segments)-1]
			}
			moduleSegments := append(splitPath(logicalRoot), segments...)
			sourceText, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			relativeSourcePath := relativeTo(projectRoot, normalizedPath)
			modules = append(modules, ModuleInfo{
				ModuleID:           strings.Join(moduleSegments, "."),
				SourcePath:         normalizedPath,
				RelativeSourcePath: relativeSourcePath,
				SourceName:         strings.TrimSuffix(relativeSourcePath, ".lua"),
				SourceText:         string(sourceText),
			})
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	sort.Slice(modules, func(i, j int) bool {
		return modules[i].RelativeSourcePath < modules[j].RelativeSourcePath
	})
	return modules, nil
}

func analyzeModules(projectRoot string, modules []ModuleInfo) ([]functionInfo, error) {
	cachePath := cachePathForProject(projectRoot)
	cache, _ := loadCache(cachePath)
	if cache.Entries == nil {
		cache.Entries = map[string]cacheEntry{}
	}

	type task struct {
		Index  int
		Module ModuleInfo
		Hash   string
	}
	type result struct {
		Index     int
		Functions []functionInfo
		Hash      string
		Err       error
	}

	tasks := make(chan task)
	results := make(chan result, len(modules))
	workerCount := runtime.NumCPU()
	if workerCount < 1 {
		workerCount = 1
	}

	var wg sync.WaitGroup
	for range workerCount {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for task := range tasks {
				functions, err := analyzeModule(task.Module)
				results <- result{Index: task.Index, Functions: functions, Hash: task.Hash, Err: err}
			}
		}()
	}

	resolved := make([][]functionInfo, len(modules))
	pending := 0
	for index, module := range modules {
		hash := hashText(module.SourceText)
		entry, ok := cache.Entries[module.RelativeSourcePath]
		if ok && entry.SourceHash == hash {
			resolved[index] = cloneFunctions(entry.Functions)
			continue
		}
		pending++
		tasks <- task{Index: index, Module: module, Hash: hash}
	}
	close(tasks)

	var firstErr error
	for pending > 0 {
		item := <-results
		pending--
		if item.Err != nil && firstErr == nil {
			firstErr = item.Err
		}
		if item.Err == nil {
			resolved[item.Index] = item.Functions
			cache.Entries[modules[item.Index].RelativeSourcePath] = cacheEntry{SourceHash: item.Hash, Functions: cloneFunctions(item.Functions)}
		}
	}
	wg.Wait()
	if firstErr != nil {
		return nil, firstErr
	}
	_ = saveCache(cachePath, cache)

	var all []functionInfo
	for _, list := range resolved {
		all = append(all, list...)
	}
	return all, nil
}

func analyzeModule(module ModuleInfo) ([]functionInfo, error) {
	if _, err := exec.LookPath("luac"); err != nil {
		return nil, fmt.Errorf("luac not found: %w", err)
	}
	command := exec.Command("luac", "-p", "-l", module.SourcePath)
	var output bytes.Buffer
	command.Stdout = &output
	command.Stderr = &output
	if err := command.Run(); err != nil {
		return nil, fmt.Errorf("luac failed: %s", strings.TrimSpace(output.String()))
	}
	chunks := parseLuacOutput(output.String())
	namesByLine := extractNames(module.SourceText)
	functions := make([]functionInfo, 0, len(chunks))
	for index, chunk := range chunks {
		executableLines := collectLines(chunk.Instructions)
		decisionInstructions := make([]instruction, 0)
		for _, item := range chunk.Instructions {
			if decisionOpcodes[item.Opcode] {
				decisionInstructions = append(decisionInstructions, item)
			}
		}
		decisionLines := collectLines(decisionInstructions)
		name := consumeName(namesByLine, chunk.StartLine)
		if name == "" {
			name = fmt.Sprintf("anonymous@%d", fallbackLine(chunk.StartLine, index+1))
		}
		functions = append(functions, functionInfo{
			ID:                 fmt.Sprintf("%s::%s:%d", module.ModuleID, name, fallbackLine(chunk.StartLine, index+1)),
			Name:               name,
			ModuleID:           module.ModuleID,
			SourceName:         module.SourceName,
			SourcePath:         module.SourcePath,
			RelativeSourcePath: module.RelativeSourcePath,
			StartLine:          chunk.StartLine,
			EndLine:            chunk.EndLine,
			ExecutableLines:    executableLines,
			DecisionLines:      decisionLines,
			Complexity:         1 + len(decisionLines),
		})
	}
	return functions, nil
}

func buildFunctions(functions []functionInfo, hits map[string]map[string]bool) []ipc.ReportFunction {
	rows := make([]ipc.ReportFunction, 0, len(functions))
	for _, fn := range functions {
		pathHits := hits[fn.RelativeSourcePath]
		hitCount := 0
		for _, line := range fn.ExecutableLines {
			if pathHits != nil && pathHits[strconv.Itoa(line)] {
				hitCount++
			}
		}
		executableCount := len(fn.ExecutableLines)
		coverageRatio := 0.0
		if executableCount > 0 {
			coverageRatio = float64(hitCount) / float64(executableCount)
		}
		crapScore := float64(fn.Complexity*fn.Complexity)*pow3(1-coverageRatio) + float64(fn.Complexity)
		rows = append(rows, ipc.ReportFunction{
			ID:                  fn.ID,
			Name:                fn.Name,
			ModuleID:            fn.ModuleID,
			SourceName:          fn.SourceName,
			SourcePath:          fn.RelativeSourcePath,
			StartLine:           fn.StartLine,
			EndLine:             fn.EndLine,
			ExecutableLines:     cloneInts(fn.ExecutableLines),
			ExecutableLineCount: executableCount,
			HitLineCount:        hitCount,
			Coverage:            roundScore(coverageRatio),
			Complexity:          fn.Complexity,
			DecisionLineCount:   len(fn.DecisionLines),
			CRAP:                roundScore(crapScore),
			RiskBand:            riskBand(crapScore),
		})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].CRAP == rows[j].CRAP {
			if rows[i].Complexity == rows[j].Complexity {
				return rows[i].ID < rows[j].ID
			}
			return rows[i].Complexity > rows[j].Complexity
		}
		return rows[i].CRAP > rows[j].CRAP
	})
	return rows
}

func buildModules(modules []ModuleInfo, functions []ipc.ReportFunction, hits map[string]map[string]bool) []ipc.ReportModule {
	functionsByPath := map[string][]ipc.ReportFunction{}
	for _, fn := range functions {
		functionsByPath[fn.SourcePath] = append(functionsByPath[fn.SourcePath], fn)
	}
	rows := make([]ipc.ReportModule, 0, len(modules))
	for _, module := range modules {
		moduleFunctions := functionsByPath[module.RelativeSourcePath]
		maxCRAP := 0.0
		totalCRAP := 0.0
		for _, fn := range moduleFunctions {
			totalCRAP += fn.CRAP
			if fn.CRAP > maxCRAP {
				maxCRAP = fn.CRAP
			}
		}
		rows = append(rows, ipc.ReportModule{
			ModuleID:        module.ModuleID,
			SourceName:      module.SourceName,
			SourcePath:      module.RelativeSourcePath,
			FunctionCount:   len(moduleFunctions),
			HitLineCount:    countHitLines(hits[module.RelativeSourcePath]),
			MaxFunctionCRAP: roundScore(maxCRAP),
			TotalCRAP:       roundScore(totalCRAP),
		})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].MaxFunctionCRAP == rows[j].MaxFunctionCRAP {
			return rows[i].SourcePath < rows[j].SourcePath
		}
		return rows[i].MaxFunctionCRAP > rows[j].MaxFunctionCRAP
	})
	return rows
}

func parseLuacOutput(output string) []functionChunk {
	var functions []functionChunk
	var current *functionChunk
	for _, line := range strings.Split(output+"\n", "\n") {
		matches := headerPattern.FindStringSubmatch(line)
		if matches != nil {
			if current != nil && current.Kind == "function" {
				functions = append(functions, *current)
			}
			startLine, _ := strconv.Atoi(matches[3])
			endLine, _ := strconv.Atoi(matches[4])
			current = &functionChunk{Kind: matches[1], StartLine: startLine, EndLine: endLine}
			continue
		}
		matches = instructionPattern.FindStringSubmatch(line)
		if matches != nil && current != nil && current.Kind == "function" {
			lineNo, _ := strconv.Atoi(matches[1])
			current.Instructions = append(current.Instructions, instruction{SourceLine: lineNo, Opcode: matches[2]})
		}
	}
	if current != nil && current.Kind == "function" {
		functions = append(functions, *current)
	}
	return functions
}

func extractNames(sourceText string) map[int][]string {
	names := map[int][]string{}
	for index, line := range strings.Split(sourceText, "\n") {
		lineNo := index + 1
		appendName(names, lineNo, firstMatch(localNamePattern, line))
		appendName(names, lineNo, firstMatch(globalNamePattern, line))
		appendName(names, lineNo, firstMatch(assignNamePattern, line))
	}
	return names
}

func appendName(names map[int][]string, lineNo int, name string) {
	if name == "" {
		return
	}
	names[lineNo] = append(names[lineNo], name)
}

func consumeName(names map[int][]string, lineNo int) string {
	bucket := names[lineNo]
	if len(bucket) == 0 {
		return ""
	}
	name := bucket[0]
	names[lineNo] = bucket[1:]
	return name
}

func firstMatch(pattern *regexp.Regexp, line string) string {
	matches := pattern.FindStringSubmatch(line)
	if len(matches) < 2 {
		return ""
	}
	return matches[1]
}

func collectLines(items []instruction) []int {
	seen := map[int]bool{}
	var lines []int
	for _, item := range items {
		if item.SourceLine > 0 && !seen[item.SourceLine] {
			seen[item.SourceLine] = true
			lines = append(lines, item.SourceLine)
		}
	}
	sort.Ints(lines)
	return lines
}

func defaultProjectName(projectName string, projectRoot string) string {
	if strings.TrimSpace(projectName) != "" {
		return projectName
	}
	projectRoot = normalizePath(projectRoot)
	parts := splitPath(projectRoot)
	if len(parts) == 0 {
		return "project"
	}
	return parts[len(parts)-1]
}

func riskBand(crapScore float64) string {
	if crapScore > 30 {
		return "critical"
	}
	if crapScore >= 10 {
		return "warning"
	}
	return "low"
}

func roundScore(value float64) float64 {
	return float64(int(value*100+0.5)) / 100
}

func pow3(value float64) float64 {
	return value * value * value
}

func countHitLines(lines map[string]bool) int {
	count := 0
	for _, hit := range lines {
		if hit {
			count++
		}
	}
	return count
}

func fallbackLine(line int, fallback int) int {
	if line > 0 {
		return line
	}
	return fallback
}

func normalizePath(path string) string {
	return strings.ReplaceAll(filepath.Clean(path), "\\", "/")
}

func relativeTo(root string, path string) string {
	root = strings.TrimSuffix(normalizePath(root), "/")
	path = strings.TrimPrefix(normalizePath(path), "@")
	path = strings.TrimPrefix(path, "./")
	if root != "" && strings.HasPrefix(path, root) {
		suffix := strings.TrimPrefix(path[len(root):], "/")
		if suffix != "" {
			return suffix
		}
	}
	return path
}

func splitPath(path string) []string {
	normalized := normalizePath(path)
	if normalized == "." || normalized == "" || normalized == "/" {
		return nil
	}
	parts := strings.Split(normalized, "/")
	filtered := make([]string, 0, len(parts))
	for _, part := range parts {
		if part != "" && part != "." {
			filtered = append(filtered, part)
		}
	}
	return filtered
}

func hashText(text string) string {
	sum := sha256.Sum256([]byte(text))
	return hex.EncodeToString(sum[:])
}

func cloneInts(values []int) []int {
	cloned := make([]int, len(values))
	copy(cloned, values)
	return cloned
}

func cloneStrings(values []string) []string {
	cloned := make([]string, len(values))
	copy(cloned, values)
	return cloned
}

func cloneFunctions(values []functionInfo) []functionInfo {
	cloned := make([]functionInfo, len(values))
	for index, fn := range values {
		cloned[index] = fn
		cloned[index].ExecutableLines = cloneInts(fn.ExecutableLines)
		cloned[index].DecisionLines = cloneInts(fn.DecisionLines)
	}
	return cloned
}

func cachePathForProject(projectRoot string) string {
	base, err := os.UserCacheDir()
	if err != nil || base == "" {
		base = os.TempDir()
	}
	projectHash := hashText(projectRoot)
	return filepath.Join(base, "crap4lua-go", projectHash+".json")
}

func loadCache(path string) (cacheFile, error) {
	var value cacheFile
	content, err := os.ReadFile(path)
	if err != nil {
		return value, err
	}
	if err := json.Unmarshal(content, &value); err != nil {
		return cacheFile{}, err
	}
	if value.Version != cacheVersion {
		return cacheFile{Version: cacheVersion, Entries: map[string]cacheEntry{}}, nil
	}
	return value, nil
}

func saveCache(path string, value cacheFile) error {
	value.Version = cacheVersion
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	content, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return os.WriteFile(path, content, 0o644)
}
