package ipc

import (
	"encoding/json"
	"os"
)

type CoverageResult struct {
	LineHits LineHits     `json:"line_hits"`
	Lanes    []LaneResult `json:"lanes"`
}

type LineHits map[string]map[string]bool

type LaneResult struct {
	Lane         string        `json:"lane"`
	Mode         string        `json:"mode"`
	Total        int           `json:"total"`
	Failed       bool          `json:"failed"`
	FailureCount int           `json:"failure_count"`
	Failures     []interface{} `json:"failures"`
}

type ReportRequest struct {
	ProjectRoot    string         `json:"project_root"`
	ProjectName    string         `json:"project_name"`
	SourceRoots    []string       `json:"source_roots"`
	CoverageResult CoverageResult `json:"coverage_result"`
	Top            int            `json:"top"`
	StrictTests    bool           `json:"strict_tests"`
}

type ReportMetadata struct {
	Tool          string   `json:"tool"`
	SchemaVersion int      `json:"schema_version"`
	Engine        string   `json:"engine"`
	ProjectRoot   string   `json:"project_root"`
	ProjectName   string   `json:"project_name"`
	SourceRoots   []string `json:"source_roots"`
	GeneratedAt   string   `json:"generated_at"`
}

type ReportSummary struct {
	ModuleCount           int     `json:"module_count"`
	FunctionCount         int     `json:"function_count"`
	TotalCRAP             float64 `json:"total_crap"`
	CriticalFunctionCount int     `json:"critical_function_count"`
}

type ReportModule struct {
	ModuleID        string  `json:"module_id"`
	SourceName      string  `json:"source_name"`
	SourcePath      string  `json:"source_path"`
	FunctionCount   int     `json:"function_count"`
	HitLineCount    int     `json:"hit_line_count"`
	MaxFunctionCRAP float64 `json:"max_function_crap"`
	TotalCRAP       float64 `json:"total_crap"`
}

type ReportFunction struct {
	ID                  string  `json:"id"`
	Name                string  `json:"name"`
	ModuleID            string  `json:"module_id"`
	SourceName          string  `json:"source_name"`
	SourcePath          string  `json:"source_path"`
	StartLine           int     `json:"start_line"`
	EndLine             int     `json:"end_line"`
	ExecutableLines     []int   `json:"executable_lines"`
	ExecutableLineCount int     `json:"executable_line_count"`
	HitLineCount        int     `json:"hit_line_count"`
	Coverage            float64 `json:"coverage"`
	Complexity          int     `json:"complexity"`
	DecisionLineCount   int     `json:"decision_line_count"`
	CRAP                float64 `json:"crap"`
	RiskBand            string  `json:"risk_band"`
}

type ReportResponse struct {
	Metadata  ReportMetadata   `json:"metadata"`
	Summary   ReportSummary    `json:"summary"`
	Lanes     []LaneResult     `json:"lanes"`
	Modules   []ReportModule   `json:"modules"`
	Functions []ReportFunction `json:"functions"`
	ExitCode  int              `json:"exit_code"`
}

func ReadJSON[T any](path string) (T, error) {
	var value T
	content, err := os.ReadFile(path)
	if err != nil {
		return value, err
	}
	err = json.Unmarshal(content, &value)
	return value, err
}

func WriteJSON(path string, value any) error {
	content, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return os.WriteFile(path, content, 0o644)
}

func (hits *LineHits) UnmarshalJSON(data []byte) error {
	if string(data) == "[]" || string(data) == "null" {
		*hits = LineHits{}
		return nil
	}
	var decoded map[string]map[string]bool
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	*hits = LineHits(decoded)
	return nil
}
