#!/bin/bash
# Spread the Master
# Merge master branch into all other branches
# - On GitHub Actions: fail immediately on conflicts
# - On local: wait and retry every 10s until conflicts resolved

set -e

MASTER_BRANCH="master"
CONFLICT_CHECK_INTERVAL=10
UNTRACKED_ZIP="untracked_files.zip"
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
# ZIP/UNZIP HELPERS (Windows PowerShell fallback)
# ==========================================
do_zip() {
    local zip_file="$1"
    shift
    local files=("$@")

    if command -v zip &> /dev/null; then
        printf '%s\n' "${files[@]}" | zip -@ "$zip_file" > /dev/null
    elif is_windows; then
        # Use PowerShell Compress-Archive
        local win_zip_path
        win_zip_path=$(cygpath -w "$PROJECT_ROOT/$zip_file" 2>/dev/null || echo "$PROJECT_ROOT/$zip_file")

        # Create temp file list for PowerShell
        local file_list=""
        for f in "${files[@]}"; do
            local win_path
            win_path=$(cygpath -w "$PROJECT_ROOT/$f" 2>/dev/null || echo "$PROJECT_ROOT/$f")
            file_list+="'$win_path',"
        done
        file_list="${file_list%,}"  # Remove trailing comma

        powershell.exe -NoProfile -Command "Compress-Archive -Path @($file_list) -DestinationPath '$win_zip_path' -Force" 2>/dev/null
    else
        error "No zip tool available"
        return 1
    fi
}

do_unzip() {
    local zip_file="$1"
    local dest_dir="$2"

    if command -v unzip &> /dev/null; then
        unzip -o "$zip_file" -d "$dest_dir" > /dev/null
    elif is_windows; then
        local win_zip_path win_dest_path
        win_zip_path=$(cygpath -w "$zip_file" 2>/dev/null || echo "$zip_file")
        win_dest_path=$(cygpath -w "$dest_dir" 2>/dev/null || echo "$dest_dir")

        powershell.exe -NoProfile -Command "Expand-Archive -Path '$win_zip_path' -DestinationPath '$win_dest_path' -Force" 2>/dev/null
    else
        error "No unzip tool available"
        return 1
    fi
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
        log "Found untracked files, backing up to $UNTRACKED_ZIP..."

        # Remove old zip if exists
        rm -f "$PROJECT_ROOT/$UNTRACKED_ZIP"

        # Create zip preserving relative paths
        cd "$PROJECT_ROOT"

        # Convert newline-separated list to array
        local files_array=()
        while IFS= read -r f; do
            [[ -n "$f" ]] && files_array+=("$f")
        done <<< "$UNTRACKED_FILES"

        if do_zip "$UNTRACKED_ZIP" "${files_array[@]}"; then
            log "Backed up ${#files_array[@]} untracked files"

            # Remove untracked files to prevent interference
            for f in "${files_array[@]}"; do
                rm -f "$PROJECT_ROOT/$f"
            done
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

    # Restore untracked files from zip
    if [[ -f "$PROJECT_ROOT/$UNTRACKED_ZIP" ]]; then
        log "Restoring untracked files from $UNTRACKED_ZIP..."
        if do_unzip "$PROJECT_ROOT/$UNTRACKED_ZIP" "$PROJECT_ROOT"; then
            rm -f "$PROJECT_ROOT/$UNTRACKED_ZIP"
            log "Untracked files restored"
        else
            error "Failed to restore untracked files - zip kept at $PROJECT_ROOT/$UNTRACKED_ZIP"
        fi
    else
        log "No untracked files backup to restore"
    fi

    # Return to original branch if different
    if [[ -n "$ORIGINAL_BRANCH" && "$ORIGINAL_BRANCH" != "$MASTER_BRANCH" ]]; then
        log "Returning to original branch: $ORIGINAL_BRANCH"
        git checkout "$ORIGINAL_BRANCH"
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
