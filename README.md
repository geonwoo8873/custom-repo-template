# Custom GitHub Template

This repository provides a GitHub Pull Request automation template designed for team workflows that value clear review communication, consistent labeling, and automated task ownership. It is structured around a Korean-first collaboration style, but it can also be adapted for international repositories that need a more standardized PR process.

## Overview

In many repositories, PR templates are treated as static forms. However, a well-designed PR template can do much more than just organize sections. It can improve review quality, reduce manual follow-up work, and make the change history easier to understand.

This template is built to address common PR workflow issues such as:

- automatically inserting a commit summary into the PR body
- assigning labels based on changed file types
- inferring additional labels from branch naming conventions
- automatically assigning assignees to clarify ownership
- keeping the PR description readable for both reviewers and maintainers

## Key Features

### 1. Automatic Commit Summary Injection

If the PR template contains the placeholder `__COMMIT_SHA__`, the GitHub Actions script reads the pull request commit list and inserts a line-by-line summary into the PR body.

This is useful because it keeps a full record of the commits included in the PR without flattening everything into a single SHA string.

### 2. Label Classification Based on Changed Files

The workflow inspects the changed files and assigns labels according to the following logic:

- documentation-only changes: `document`
- any code changes: `enhancement`

If the PR contains both documentation and code changes, the code-related label is prioritized.

### 3. Additional Branch-Based Labels

Branch names are also inspected to add metadata labels such as:

- `refactor` when the branch name includes `refactor`
- `bug` when the branch name includes `bug`, `fix`, `hotfix`, or `bugfix`
- `release` when the branch name includes `release`

The file-based label is treated as the primary label, while the branch-based label acts as an additional signal.

### 4. Automatic Assignee Assignment

The automation assigns the PR author as the default assignee. If needed, you can override this behavior by setting `PR_ASSIGNEES` in the workflow environment.

Examples:

```yaml
env:
  PR_ASSIGNEES: username
```

```yaml
env:
  PR_ASSIGNEES: username,team-lead
```

## Repository Structure

```text
.github/
├── PULL_REQUEST_TEMPLATE/
│   └── pull_request_template.md
├── scripts/
│   └── pull-request-temp-apply.sh
├── workflows/
│   └── config.yml
README.md
README.en.md
```

## Example PR Template

The template is intentionally written to be readable for humans while still supporting machine-driven automation.

```md
## 주요 변경 사항 (Key Changes)
<!-- Please briefly describe the core changes in this PR. -->
- [Key change 1]
- [Key change 2]
- [Key change 3]

#### 커밋 요약:
__COMMIT_SHA__

#### 변경 내용:
<!-- Describe the reason for the change, impacted areas, and any notes for reviewers. -->
```

This format keeps the PR purpose clear while preserving a structured, automated commit summary section.

## Automation Flow

1. A `pull_request` event triggers the GitHub Actions workflow.
2. The script reads the event payload and GitHub API metadata from the environment.
3. It retrieves the PR commit list and builds a summary string.
4. It inspects the changed files and assigns a primary label: `document` or `enhancement`.
5. It inspects the branch name and optionally adds `refactor`, `bug`, or `release`.
6. Missing labels are created if necessary.
7. The commit summary replaces the `__COMMIT_SHA__` placeholder in the PR template.
8. The PR author is set as the default assignee unless a custom assignee list is provided.

## Label Rules

The default label logic is:

- documentation-only PR: `document`
- code-related PR: `enhancement`
- branch contains `refactor`: `refactor`
- branch contains `bug`, `fix`, `hotfix`, or `bugfix`: `bug`
- branch contains `release`: `release`

Duplicate labels are removed so a single PR does not receive redundant entries.

## GitHub Actions Configuration

The workflow passes the following environment variables to the script:

- `GITHUB_TOKEN`
- `GITHUB_EVENT_PATH`
- `GITHUB_REPOSITORY`
- `GITHUB_API_URL`
- `PR_ASSIGNEES` (optional)

The main workflow logic is defined in [.github/workflows/config.yml](.github/workflows/config.yml), while the PR update behavior lives in [.github/scripts/pull-request-temp-apply.sh](.github/scripts/pull-request-temp-apply.sh).

## How to Use It

1. Open or update a pull request in the repository.
2. The PR template is automatically loaded.
3. The workflow calculates commit metadata, labels, and assignees.
4. The PR body is updated with the generated summary.
5. Reviewers can then focus on the meaningful change description instead of manually reconstructing commit history.

## Notes

- Human-written PR descriptions are still preferable for explaining the business or technical intent of the change.
- Automatically generated commit summaries are best used as structured metadata rather than a complete replacement for meaningful documentation.
- GitHub Actions behavior depends on repository permissions, branch conditions, and token scope.
- For public repositories, workflow permissions and event triggers should be reviewed carefully to avoid accidental privilege exposure.

## License

This project is provided as a reusable example template for team collaboration and can be adapted to fit the conventions of your organization or open-source community.

You are free to customize the labels, branch rules, and template language to match your project's operating model.

