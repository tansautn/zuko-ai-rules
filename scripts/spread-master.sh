#!/bin/bash
# Spread the Master
# Merge master branch into all other branches
# - On GitHub Actions: fail immediately on conflicts
# - On local: wait and retry every 10s until conflicts resolved

set -e

MASTER_BRANCH="master"
CONFLICT_CHECK_INTERVAL=10
UNTRACKED_ARCHIVE="untracked_files.tar.gz"
PROJECT_ROOT=$(git rev-parse --show-toplevel)

# Detect if running in CI
is_ci() {
    [[ -n "$GITHUB_ACTIONS" || -n "$CI" ]]
}

is_windows() {
    [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]] || [[ -n "${WINDIR:-}" ]]
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    log "ERROR: $*" >&2
}


# ==========================================
# PRE-RUN STAGE
# ==========================================
pre_run() {
    log "=== PRE-RUN STAGE ==="

    ORIGINAL_BRANCH=$(git branch --show-current)

    # 1. Check for tracked files with changes
    CHANGED_FILES=$(git diff --name-only)
    STAGED_FILES=$(git diff --cached --name-only)

    if [[ -n "$CHANGED_FILES" || -n "$STAGED_FILES" ]]; then
        error "Tracked files have uncommitted changes!"
        error "Branch: $ORIGINAL_BRANCH"
        echo "Changed files:"
        [[ -n "$CHANGED_FILES" ]] && echo "$CHANGED_FILES" | sed 's/^/  - /'
        [[ -n "$STAGED_FILES" ]] && echo "$STAGED_FILES" | sed 's/^/  - (staged) /'
        exit 1
    fi
    log "No uncommitted tracked changes. OK"

    # 2. Switch to master if not already
    if [[ "$ORIGINAL_BRANCH" != "$MASTER_BRANCH" ]]; then
        if is_ci; then
            error "CI must run on $MASTER_BRANCH branch, but current is: $ORIGINAL_BRANCH"
            exit 1
        fi
        log "Switching from '$ORIGINAL_BRANCH' to '$MASTER_BRANCH'..."
        git checkout "$MASTER_BRANCH"
    fi

    # Pull latest master
    log "Pulling latest $MASTER_BRANCH from origin..."
    git pull origin "$MASTER_BRANCH" --ff-only || git pull origin "$MASTER_BRANCH"

    # 3. Handle untracked files - zip them
    UNTRACKED_FILES=$(git ls-files --others --exclude-standard)

    if [[ -n "$UNTRACKED_FILES" ]]; then
        log "Found untracked files, backing up to $UNTRACKED_ARCHIVE..."

        # Remove old archive if exists
        rm -f "$PROJECT_ROOT/$UNTRACKED_ARCHIVE"

        cd "$PROJECT_ROOT"

        # Use tar (available in Git Bash) - preserves symlinks with -h
        if echo "$UNTRACKED_FILES" | tar -czhf "$UNTRACKED_ARCHIVE" -T - 2>/dev/null; then
            log "Backed up $(echo "$UNTRACKED_FILES" | wc -l | xargs) untracked items"

            # Remove untracked files/dirs/symlinks
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                local full_path="$PROJECT_ROOT/$f"
                if [[ -L "$full_path" ]]; then
                    rm -f "$full_path" 2>/dev/null || true
                elif [[ -d "$full_path" ]]; then
                    rm -rf "$full_path"
                else
                    rm -f "$full_path"
                fi
            done <<< "$UNTRACKED_FILES"
        else
            error "Failed to backup untracked files"
            exit 1
        fi
    else
        log "No untracked files to backup"
    fi

    log "=== PRE-RUN COMPLETE ==="
    echo ""
}

# ==========================================
# POST-RUN STAGE
# ==========================================
post_run() {
    echo ""
    log "=== POST-RUN STAGE ==="

    cd "$PROJECT_ROOT"
    # Return to original branch if different
#    if [[ -n "$ORIGINAL_BRANCH" && "$ORIGINAL_BRANCH" != "$MASTER_BRANCH" ]]; then
    if [[ -n "$ORIGINAL_BRANCH" ]]; then
        log "Returning to original branch: $ORIGINAL_BRANCH"
        git checkout "$ORIGINAL_BRANCH"
    fi
    # Restore untracked files from archive
    if [[ -f "$PROJECT_ROOT/$UNTRACKED_ARCHIVE" ]]; then
        log "Restoring untracked files from $UNTRACKED_ARCHIVE..."
        if tar -xzf "$PROJECT_ROOT/$UNTRACKED_ARCHIVE" -C "$PROJECT_ROOT"; then
            rm -f "$PROJECT_ROOT/$UNTRACKED_ARCHIVE"
            log "Untracked files restored"
        else
            error "Failed to restore untracked files - archive kept at $PROJECT_ROOT/$UNTRACKED_ARCHIVE"
        fi
    else
        log "No untracked files backup to restore"
    fi

    log "=== POST-RUN COMPLETE ==="
}

# Ensure post_run executes even on error
trap post_run EXIT

# ==========================================
# MAIN
# ==========================================

# Run pre-stage
pre_run

# Fetch all branches from origin
log "Fetching all branches from origin..."
git fetch --all --prune

# Store original branch (already captured in pre_run)
# ORIGINAL_BRANCH is already set

# Get list of all remote branches (excluding master and HEAD)
BRANCHES=$(git branch -r | grep -v "HEAD" | grep -v "origin/$MASTER_BRANCH" | sed 's|origin/||' | xargs)

if [[ -z "$BRANCHES" ]]; then
    log "No branches found to update (other than $MASTER_BRANCH)"
    exit 0
fi

log "Branches to update: $BRANCHES"

# Track failed branches
FAILED_BRANCHES=()

# Process each branch
for branch in $BRANCHES; do
    log "Processing branch: $branch"

    # Check if local branch exists, create if not
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        log "  Creating local branch '$branch' from origin/$branch"
        git branch "$branch" "origin/$branch"
    fi

    # Checkout the branch
    git checkout "$branch"

    # Pull latest from origin
    git pull origin "$branch" --ff-only 2>/dev/null || git pull origin "$branch" --rebase=false || true

    # Attempt merge
    log "  Merging $MASTER_BRANCH into $branch..."

    while true; do
        if git merge "$MASTER_BRANCH" --no-edit; then
            log "  Merge successful!"

            # Push if there are changes
            if [[ $(git rev-list "origin/$branch..$branch" --count) -gt 0 ]]; then
                log "  Pushing changes to origin/$branch..."
                git push origin "$branch"
            else
                log "  No new commits to push"
            fi
            break
        else
            # Merge failed - check for conflicts
            if git diff --name-only --diff-filter=U | grep -q .; then
                # There are conflicts
                CONFLICTED_FILES=$(git diff --name-only --diff-filter=U | tr '\n' ' ')

                if is_ci; then
                    error "Conflicts detected in branch '$branch': $CONFLICTED_FILES"
                    error "Aborting merge and failing CI..."
                    git merge --abort
                    FAILED_BRANCHES+=("$branch")
                    break
                else
                    # Local mode - wait for user to resolve
                    echo ""
                    echo "=========================================="
                    error "CONFLICTS detected in branch '$branch'"
                    echo "Conflicted files: $CONFLICTED_FILES"
                    echo "Please resolve conflicts manually, then:"
                    echo "  git add <resolved-files>"
                    echo "  git commit"
                    echo "Waiting... (checking every ${CONFLICT_CHECK_INTERVAL}s)"
                    echo "=========================================="
                    echo ""

                    while git diff --name-only --diff-filter=U | grep -q .; do
                        sleep "$CONFLICT_CHECK_INTERVAL"
                        log "  Still waiting for conflict resolution in '$branch'..."
                    done

                    log "  Conflicts resolved! Continuing..."

                    # Push after resolution
                    if [[ $(git rev-list "origin/$branch..$branch" --count) -gt 0 ]]; then
                        log "  Pushing changes to origin/$branch..."
                        git push origin "$branch"
                    fi
                    break
                fi
            else
                # Merge failed but no conflicts - something else wrong
                error "Merge failed for unknown reason in branch '$branch'"
                git merge --abort 2>/dev/null || true
                FAILED_BRANCHES+=("$branch")
                break
            fi
        fi
    done
done

# Summary (post_run handles branch restore via trap)
echo ""
echo "=========================================="
log "SUMMARY"
echo "=========================================="
log "Total branches processed: $(echo $BRANCHES | wc -w | xargs)"

if [[ ${#FAILED_BRANCHES[@]} -gt 0 ]]; then
    error "Failed branches: ${FAILED_BRANCHES[*]}"
    exit 1
else
    log "All branches updated successfully!"
    exit 0
fi
