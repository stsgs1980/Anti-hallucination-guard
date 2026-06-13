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

REPO="stsgs1980/Anti-hallucination-guard"
BRANCH="main"

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
# This requires a GitHub token with repo admin scope
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
        "required_approving_review_count": 1
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
echo "  [x] Require PR before merging (1 approval required)"
echo "  [x] Require review from Code Owners (@stsgs1980)"
echo "  [x] Dismiss stale reviews on push"
echo "  [x] Require status checks to pass (CI + PR guard)"
echo "  [x] Require linear history (no merge commits)"
echo "  [x] Block force pushes"
echo "  [x] Block branch deletion"
echo "  [x] Enforce for admins too"
echo ""
echo "NO consumer project agent can now:"
echo "  - Push directly to main"
echo "  - Merge their own PRs without owner approval"
echo "  - Force-push or delete the branch"
echo "  - Bypass Code Owner review"
echo ""
echo "Rule 17 enforcement is COMPLETE."
