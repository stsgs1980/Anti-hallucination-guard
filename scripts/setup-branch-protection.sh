#!/bin/bash
# anti-hallucination-guard / setup-branch-protection.sh
# Configures GitHub branch protection on the 'main' branch.
# This is the LAST enforcement layer for Rule 17 (upstream write protection).
#
# PREREQUISITES:
#   1. GitHub CLI (gh) must be installed and authenticated
#   2. You must have admin access to the repository
#   3. Run this ONCE after creating the repository
#
# USAGE:
#   bash scripts/setup-branch-protection.sh
#
# This script requires 'gh' CLI. Install it:
#   https://cli.github.com/
#
# After installing, authenticate:
#   gh auth login

set -euo pipefail

# Auto-detect repository from git remote (no hardcoding)
BRANCH="main"

REPO=""
if command -v gh &>/dev/null; then
    REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
fi
if [ -z "$REPO" ]; then
    # Fallback: parse git remote URL
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$REMOTE_URL" ]; then
        # Handle both https://github.com/owner/repo.git and git@github.com:owner/repo.git
        REPO=$(echo "$REMOTE_URL" | sed -E 's|.*github.com[:/]([^/]+/[^/]+)(\.git)?$|\1|' 2>/dev/null || echo "")
    fi
fi
if [ -z "$REPO" ]; then
    echo "ERROR: Could not auto-detect repository name."
    echo "  Ensure you are inside the git repo with a github remote."
    echo "  Or set REPO manually: REPO=owner/repo bash scripts/setup-branch-protection.sh"
    exit 1
fi

echo "=== AHG Branch Protection Setup ==="
echo ""
echo "Repository: $REPO"
echo "Branch:     $BRANCH"
echo ""

# Check if gh CLI is available
if ! command -v gh &>/dev/null; then
    echo "ERROR: GitHub CLI (gh) is not installed."
    echo "  Install: https://cli.github.com/"
    echo "  Then:    gh auth login"
    echo "  Then:    re-run this script"
    exit 1
fi

# Check if authenticated
if ! gh auth status &>/dev/null; then
    echo "ERROR: GitHub CLI is not authenticated."
    echo "  Run: gh auth login"
    exit 1
fi

echo "Configuring branch protection for $BRANCH..."
echo ""

# Set branch protection using GitHub API
# IMPORTANT: required_approving_review_count is 0 (no approval required)
# because this is a solo-developer project. Setting it to 1 creates a deadlock:
# the only contributor cannot merge their own PRs.
# CODEOWNERS review is still required for security.
# Branch protection still blocks: force pushes, deletions, direct pushes to main.
gh api \
    "repos/$REPO/branches/$BRANCH/protection" \
    --method PUT \
    --input - <<'EOF'
{
    "required_status_checks": {
        "strict": true,
        "contexts": ["Module purity + fingerprints + verify-docs", "verify-docs self-test", "Upstream write protection"]
    },
    "enforce_admins": true,
    "required_pull_request_reviews": {
        "dismiss_stale_reviews": true,
        "require_code_owner_reviews": true,
        "required_approving_review_count": 0
    },
    "restrictions": null,
    "required_linear_history": true,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "block_creations": true
}
EOF

echo ""
echo "=== Branch protection configured ==="
echo ""
echo "Protection rules on '$BRANCH':"
echo "  [x] Require PR before merging (no approval required -- solo developer)"
echo "  [x] Require review from Code Owners (CODEOWNERS file)"
echo "  [x] Dismiss stale reviews on push"
echo "  [x] Require status checks to pass (CI + PR guard)"
echo "  [x] Require linear history (no merge commits)"
echo "  [x] Block force pushes"
echo "  [x] Block branch deletion"
echo "  [x] Enforce for admins too"
echo ""
echo "NOTE: required_approving_review_count = 0 (solo developer mode)"
echo "  Setting it to 1 creates a deadlock: the only contributor cannot merge own PRs."
echo "  CODEOWNERS review is still enforced via require_code_owner_reviews."
echo ""
echo "NO consumer project agent can now:"
echo "  - Push directly to main"
echo "  - Force-push or delete the branch"
echo "  - Bypass Code Owner review"
echo ""
echo "Rule 17 enforcement is COMPLETE."
