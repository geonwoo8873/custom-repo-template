// Approach:
// - GitHub Actions CLI-style script that reads event payload from GITHUB_EVENT_PATH.
// - Uses GitHub REST API directly to fetch author location and update PR body.
// - Locale rule matches the JavaScript implementation: Korea -> ko, otherwise en.
//
// Libraries used:
// - Go standard library only: net/http, encoding/json, os, regexp, path/filepath, sort, strings.
// - No third-party package is required.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type Event struct {
	PullRequest *PullRequest `json:"pull_request"`
}

type PullRequest struct {
	Number int  `json:"number"`
	User   User `json:"user"`
}

type User struct {
	Login string `json:"login"`
}

type GitHubUser struct {
	Location string `json:"location"`
}

func fail(msg string) {
	fmt.Printf("::error::%s\n", msg)
	os.Exit(1)
}

func warn(msg string) {
	fmt.Printf("::warning::%s\n", msg)
}

func requestJSON(method, url, token string, in any, out any) {
	var body io.Reader
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			fail(fmt.Sprintf("failed to serialize request body: %v", err))
		}
		body = bytes.NewReader(b)
	}

	req, err := http.NewRequest(method, url, body)
	if err != nil {
		fail(fmt.Sprintf("failed to create request: %v", err))
	}

	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "update-pr-template-go")
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fail(fmt.Sprintf("github API request failed: %v", err))
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		fail(fmt.Sprintf("GitHub API error %d: %s", resp.StatusCode, string(respBody)))
	}

	if out != nil && len(respBody) > 0 {
		if err := json.Unmarshal(respBody, out); err != nil {
			fail(fmt.Sprintf("failed to parse response JSON: %v", err))
		}
	}
}

func pickTemplate(templateDir, locale string) string {
	re := regexp.MustCompile(`(?i)\.` + regexp.QuoteMeta(locale) + `\.md$`)
	entries, err := os.ReadDir(templateDir)
	if err != nil {
		fail(fmt.Sprintf("failed to read template directory: %v", err))
	}

	candidates := make([]string, 0)
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if re.MatchString(name) {
			candidates = append(candidates, name)
		}
	}

	sort.Slice(candidates, func(i, j int) bool {
		return strings.ToLower(candidates[i]) < strings.ToLower(candidates[j])
	})

	if len(candidates) == 0 {
		return ""
	}
	return filepath.Join(templateDir, candidates[0])
}

func main() {
	token := strings.TrimSpace(os.Getenv("GITHUB_TOKEN"))
	repo := strings.TrimSpace(os.Getenv("GITHUB_REPOSITORY"))
	eventPath := strings.TrimSpace(os.Getenv("GITHUB_EVENT_PATH"))
	apiURL := strings.TrimRight(strings.TrimSpace(os.Getenv("GITHUB_API_URL")), "/")
	if apiURL == "" {
		apiURL = "https://api.github.com"
	}

	if token == "" {
		fail("GITHUB_TOKEN is required")
	}
	parts := strings.SplitN(repo, "/", 2)
	if len(parts) != 2 {
		fail("GITHUB_REPOSITORY must be set as 'owner/repo'")
	}
	owner, repoName := parts[0], parts[1]
	if eventPath == "" {
		fail("GITHUB_EVENT_PATH is required")
	}

	rawEvent, err := os.ReadFile(eventPath)
	if err != nil {
		fail(fmt.Sprintf("failed to read event payload: %v", err))
	}

	var event Event
	if err := json.Unmarshal(rawEvent, &event); err != nil {
		fail(fmt.Sprintf("failed to parse event payload JSON: %v", err))
	}
	if event.PullRequest == nil {
		fail("No pull_request payload found.")
	}
	if event.PullRequest.User.Login == "" {
		fail("PR author login is missing in payload")
	}

	author := event.PullRequest.User.Login
	var ghUser GitHubUser
	requestJSON("GET", apiURL+"/users/"+author, token, nil, &ghUser)
	location := strings.TrimSpace(ghUser.Location)

	koHints := []*regexp.Regexp{
		regexp.MustCompile(`(?i)\bsouth korea\b`),
		regexp.MustCompile(`(?i)\brepublic of korea\b`),
		regexp.MustCompile(`대한민국`),
		regexp.MustCompile(`한국`),
	}

	locale := "en"
	for _, re := range koHints {
		if re.MatchString(location) {
			locale = "ko"
			break
		}
	}

	templateDir := filepath.Join(".github", "PULL_REQUEST_TEMPLATE")
	if _, err := os.Stat(templateDir); err != nil {
		fail("Template directory not found: " + templateDir)
	}

	templatePath := pickTemplate(templateDir, locale)
	if templatePath == "" {
		warn(fmt.Sprintf("No .%s.md template found. Falling back to .en.md.", locale))
		templatePath = pickTemplate(templateDir, "en")
	}
	if templatePath == "" {
		fail("No PR template found. Expected at least one .en.md file in .github/PULL_REQUEST_TEMPLATE.")
	}

	bodyBytes, err := os.ReadFile(templatePath)
	if err != nil {
		fail(fmt.Sprintf("failed to read template file: %v", err))
	}

	url := fmt.Sprintf("%s/repos/%s/%s/pulls/%d", apiURL, owner, repoName, event.PullRequest.Number)
	requestJSON("PATCH", url, token, map[string]string{"body": string(bodyBytes)}, nil)

	fmt.Printf("author=%s, location='%s', locale=%s, template='%s'\n", author, location, locale, templatePath)
}
