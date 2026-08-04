#!/bin/bash
# Spread the Master
# Merge master branch into all other branches using a clean worktree
# - On GitHub Actions: fail immediately on conflicts
# - On local: wait and retry every 10s until conflicts resolved

set -e

MASTER_BRANCH="master"
CONFLICT_CHECK_INTERVAL=10
PROJECT_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR="$PROJECT_ROOT/tmp/spread-master"

is_ci() {
    [[ -n "$GITHUB_ACTIONS" || -n "$CI" ]]
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    log "ERROR: $*" >&2
}

WORKTREE_BRANCH="_spread-master-tmp"

cleanup() {
    if [[ -d "$WORKTREE_DIR" ]]; then
        log "Cleaning up worktree..."
        git -C "$PROJECT_ROOT" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
    fi
    # Delete temp branch
    git -C "$PROJECT_ROOT" branch -D "$WORKTREE_BRANCH" 2>/dev/null || true
}

trap cleanup EXIT

# ==========================================
# SETUP
# ==========================================

# Ensure we're up-to-date
log "Fetching all branches from origin..."
git fetch --all --prune

# Remove stale worktree if exists
cleanup

# Create temp branch from master, then worktree from it
# (can't worktree add 'master' directly when it's checked out in main tree)
log "Creating temp branch '$WORKTREE_BRANCH' from $MASTER_BRANCH..."
git branch -D "$WORKTREE_BRANCH" 2>/dev/null || true
git branch "$WORKTREE_BRANCH" "$MASTER_BRANCH"

log "Creating clean worktree at $WORKTREE_DIR..."
mkdir -p "$(dirname "$WORKTREE_DIR")"
git worktree add "$WORKTREE_DIR" "$WORKTREE_BRANCH"

cd "$WORKTREE_DIR"

# Pull latest master in the worktree
log "Pulling latest $MASTER_BRANCH..."
git pull origin "$MASTER_BRANCH" --ff-only || git pull origin "$MASTER_BRANCH"

# ==========================================
# MERGE EACH BRANCH
# ==========================================

BRANCHES=$(git branch -r | grep -v "HEAD" | grep -v "origin/$MASTER_BRANCH" | sed 's|origin/||' | xargs)

if [[ -z "$BRANCHES" ]]; then
    log "No branches found to update (other than $MASTER_BRANCH)"
    exit 0
fi

log "Branches to update: $BRANCHES"

FAILED_BRANCHES=()

for branch in $BRANCHES; do
    log "Processing branch: $branch"

    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        log "  Creating local branch '$branch' from origin/$branch"
        git branch "$branch" "origin/$branch"
    fi

    git checkout "$branch"

    git pull origin "$branch" --ff-only 2>/dev/null || git pull origin "$branch" --rebase=false || true

    log "  Merging $MASTER_BRANCH into $branch..."

    while true; do
        if git merge "$MASTER_BRANCH" --no-edit; then
            log "  Merge successful!"

            if [[ $(git rev-list "origin/$branch..$branch" --count) -gt 0 ]]; then
                log "  Pushing changes to origin/$branch..."
                git push origin "$branch"
            else
                log "  No new commits to push"
            fi
            break
        else
            if git diff --name-only --diff-filter=U | grep -q .; then
                CONFLICTED_FILES=$(git diff --name-only --diff-filter=U | tr '\n' ' ')

                if is_ci; then
                    error "Conflicts detected in branch '$branch': $CONFLICTED_FILES"
                    error "Aborting merge and failing CI..."
                    git merge --abort
                    FAILED_BRANCHES+=("$branch")
                    break
                else
                    echo ""
                    echo "=========================================="
                    error "CONFLICTS detected in branch '$branch'"
                    echo "Conflicted files: $CONFLICTED_FILES"
                    echo "Resolve in: $WORKTREE_DIR"
                    echo "  cd $WORKTREE_DIR"
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

                    if [[ $(git rev-list "origin/$branch..$branch" --count) -gt 0 ]]; then
                        log "  Pushing changes to origin/$branch..."
                        git push origin "$branch"
                    fi
                    break
                fi
            else
                error "Merge failed for unknown reason in branch '$branch'"
                git merge --abort 2>/dev/null || true
                FAILED_BRANCHES+=("$branch")
                break
            fi
        fi
    done
done

# ==========================================
# SUMMARY
# ==========================================
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
