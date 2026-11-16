#!/usr/bin/env bash
set -e; F=${1:-/tmp/fixture}; rm -rf "$F"; mkdir -p "$F/docs/tasks"
cat > "$F/docs/tasks/tasks-index.md" <<'EOF'
# Project Tasks Index

## Overall Project Task Summary

- **Total Tasks**: 3
- **Pending**: 3
- **Complete**: 0

## Task File Index

- `docs/tasks/tasks-1.md`: Contains Tasks 001 - 002 (2 tasks)
- `docs/tasks/tasks-2.md`: Contains Tasks 003 - 003 (1 tasks)
EOF
cat > "$F/docs/tasks/tasks-1.md" <<'EOF'
## Summary (tasks-1.md)

- **Tasks in this file**: 2
- **Task IDs**: 001 - 002

## Tasks

### Task ID: 001

- **Title**: Create config loader
- **File**: src/config.py
- **Complete**: [x]

#### Prompt:

```markdown
**Objective:** load config
```

### Task ID: 002

- **Title**: Add CLI entry
- **File**: src/cli.py
- **Complete**: [ ]

#### Prompt:

````markdown
**Objective:** CLI with nested code:
```bash
python cli.py --help
```
````
EOF
cat > "$F/docs/tasks/tasks-2.md" <<'EOF'
## Summary (tasks-2.md)

- **Tasks in this file**: 1
- **Task IDs**: 003 - 003

## Tasks

### Task ID: 003

- **Title**: Write tests
- **File**: tests/test_cli.py
- **Complete**: [ ]

#### Prompt:

```markdown
**Objective:** tests
```
EOF
