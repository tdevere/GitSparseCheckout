#!/usr/bin/env bash
# =============================================================================
# inspect-workspace.sh – Workspace inspection for Azure DevOps sparse checkout
# =============================================================================
# Compatible with bash 3.2+ (macOS, Linux self-hosted agents).
# No external dependencies beyond bash, git, and standard POSIX utilities.
#
# Environment variables consumed:
#   SPARSE_MODE  – label injected by the calling pipeline (e.g. FULL-CHECKOUT)
#   SOURCES_DIR  – $(Build.SourcesDirectory); defaults to $PWD if not set
#
# Always exits 0 – never fails the build.
# =============================================================================
set -u   # treat unset variables as error (but we guard all reads below)

# ---------------------------------------------------------------------------
# Resolve workspace root and mode
# ---------------------------------------------------------------------------
SOURCES_DIR="${SOURCES_DIR:-$(pwd)}"
SPARSE_MODE="${SPARSE_MODE:-UNKNOWN}"

# ---------------------------------------------------------------------------
# Sentinel paths and their expected presence per mode
# Format: "relative/path|MODE1,MODE2,..."
# ---------------------------------------------------------------------------
SENTINELS=(
    "CDN/cdnfile1.txt|FULL-CHECKOUT,SPARSE-DIRECTORIES,SPARSE-PATTERNS,SPARSE-BOTH-PATTERNS-WIN"
    "CDN/cdnfile2.txt|FULL-CHECKOUT,SPARSE-DIRECTORIES,SPARSE-PATTERNS,SPARSE-BOTH-PATTERNS-WIN"
    "CDN/styles.css|FULL-CHECKOUT,SPARSE-DIRECTORIES,SPARSE-PATTERNS,SPARSE-BOTH-PATTERNS-WIN"
    "CDN/bundle.js|FULL-CHECKOUT,SPARSE-DIRECTORIES,SPARSE-PATTERNS,SPARSE-BOTH-PATTERNS-WIN"
    "CDN/nested/cdnfile2.txt|FULL-CHECKOUT,SPARSE-DIRECTORIES,SPARSE-PATTERNS,SPARSE-BOTH-PATTERNS-WIN"
    "CDN/nested/deep/asset.json|FULL-CHECKOUT,SPARSE-DIRECTORIES,SPARSE-PATTERNS,SPARSE-BOTH-PATTERNS-WIN"
    "FolderA/a1.txt|FULL-CHECKOUT"
    "FolderA/a2.txt|FULL-CHECKOUT"
    "FolderB/b1.txt|FULL-CHECKOUT"
    "FolderB/b2.txt|FULL-CHECKOUT"
    "RootFile1.yml|FULL-CHECKOUT,SPARSE-DIRECTORIES"
    "RootFile2.yml|FULL-CHECKOUT,SPARSE-DIRECTORIES"
    "config.json|FULL-CHECKOUT,SPARSE-DIRECTORIES"
    "root-notes.txt|FULL-CHECKOUT,SPARSE-DIRECTORIES"
)

SPOT_FILES=(
    "CDN/cdnfile1.txt"
    "CDN/nested/cdnfile2.txt"
    "FolderA/a1.txt"
    "RootFile1.yml"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
write_section() {
    local title="$1"
    local line
    line=$(printf '%0.s=' {1..70})
    echo ""
    echo "$line"
    echo "  $title"
    echo "$line"
}

# Returns 0 if $1 is contained (comma-separated) in $2
contains_mode() {
    local mode="$1"
    local list="$2"
    echo "$list" | tr ',' '\n' | grep -qxF "$mode"
}

# ---------------------------------------------------------------------------
# SECTION 1 – Header
# ---------------------------------------------------------------------------
write_section "WORKSPACE INSPECTION REPORT"
echo "INSPECTION_MODE    : ${SPARSE_MODE}"
echo "INSPECTION_TIME    : $(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
echo "SOURCES_DIR        : ${SOURCES_DIR}"
echo "BASH_VERSION       : ${BASH_VERSION:-unknown}"
echo "HOSTNAME           : $(hostname 2>/dev/null || echo unknown)"

# ---------------------------------------------------------------------------
# SECTION 2 – Top-level directories
# ---------------------------------------------------------------------------
write_section "TOP-LEVEL DIRECTORIES"
dir_count=0
if [ -d "${SOURCES_DIR}" ]; then
    while IFS= read -r -d '' entry; do
        name="${entry#${SOURCES_DIR}/}"
        # Only top-level items (no slash in name)
        if [[ "$name" != */* ]]; then
            if [ -d "${SOURCES_DIR}/${name}" ]; then
                echo "DIR_PRESENT        : ${name}/"
                (( dir_count++ )) || true
            fi
        fi
    done < <(find "${SOURCES_DIR}" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)
fi
echo "DIR_COUNT          : ${dir_count}"

# ---------------------------------------------------------------------------
# SECTION 3 – Top-level files
# ---------------------------------------------------------------------------
write_section "TOP-LEVEL FILES"
file_count=0
while IFS= read -r -d '' entry; do
    name=$(basename "$entry")
    echo "ROOT_FILE_PRESENT  : ${name}"
    (( file_count++ )) || true
done < <(find "${SOURCES_DIR}" -maxdepth 1 -mindepth 1 -type f -print0 | sort -z)
if [ "$file_count" -eq 0 ]; then
    echo "FILE_ENUM          : (no root-level files found)"
fi
echo "ROOT_FILE_COUNT    : ${file_count}"

# ---------------------------------------------------------------------------
# SECTION 4 – Sentinel file checks
# ---------------------------------------------------------------------------
write_section "SENTINEL FILE CHECKS"
echo ""
printf "%-45s %-8s %-10s %s\n" "PATH" "EXISTS" "EXPECTED" "OUTCOME"
printf "%-45s %-8s %-10s %s\n" "$(printf '%0.s-' {1..44})" "$(printf '%0.s─' {1..7})" "$(printf '%0.s─' {1..9})" "$(printf '%0.s─' {1..14})"

pass_count=0
fail_count=0

for entry in "${SENTINELS[@]}"; do
    rel_path="${entry%%|*}"
    expect_modes="${entry##*|}"
    full_path="${SOURCES_DIR}/${rel_path}"

    if [ -f "$full_path" ]; then
        exists="YES"
        present=1
    else
        exists="NO"
        present=0
    fi

    if contains_mode "${SPARSE_MODE}" "${expect_modes}"; then
        expected="YES"
        exp=1
    else
        expected="NO"
        exp=0
    fi

    if   [ "$exp" -eq 1 ] && [ "$present" -eq 1 ]; then
        outcome="PASS"
        (( pass_count++ )) || true
    elif [ "$exp" -eq 0 ] && [ "$present" -eq 0 ]; then
        outcome="PASS"
        (( pass_count++ )) || true
    elif [ "$exp" -eq 1 ] && [ "$present" -eq 0 ]; then
        outcome="FAIL-MISSING"
        (( fail_count++ )) || true
    else
        outcome="FAIL-UNEXPECTED"
        (( fail_count++ )) || true
    fi

    printf "%-45s %-8s %-10s %s\n" "$rel_path" "$exists" "$expected" "$outcome"
done

# ---------------------------------------------------------------------------
# SECTION 5 – Content spot-check
# ---------------------------------------------------------------------------
write_section "CONTENT SPOT-CHECK"
for rel in "${SPOT_FILES[@]}"; do
    fp="${SOURCES_DIR}/${rel}"
    if [ -f "$fp" ]; then
        sentinel_line=$(grep -m1 'SENTINEL:' "$fp" 2>/dev/null || true)
        if [ -n "$sentinel_line" ]; then
            echo "CONTENT_CHECK      : ${rel} → ${sentinel_line}"
        else
            echo "CONTENT_CHECK      : ${rel} → (no SENTINEL line found)"
        fi
    else
        echo "CONTENT_CHECK      : ${rel} → (file not present – skipped)"
    fi
done

# ---------------------------------------------------------------------------
# SECTION 6 – Git sparse-checkout introspection
# ---------------------------------------------------------------------------
write_section "GIT SPARSE-CHECKOUT INTROSPECTION"
pushd "${SOURCES_DIR}" > /dev/null 2>&1 || true

sparse_list=$(git sparse-checkout list 2>&1)
exit_code=$?
if [ "$exit_code" -eq 0 ]; then
    echo "GIT_SPARSE_LIST    :"
    echo "$sparse_list" | while IFS= read -r line; do echo "  $line"; done
else
    echo "GIT_SPARSE_LIST    : (not in sparse-checkout mode or git < 2.26)"
fi

cone_mode=$(git config core.sparseCheckoutCone 2>&1 || echo "(not set)")
echo "GIT_CONE_MODE      : ${cone_mode}"

sparse_flag=$(git config core.sparseCheckout 2>&1 || echo "(not set)")
echo "GIT_SPARSE_FLAG    : ${sparse_flag}"

popd > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# SECTION 7 – Evidence summary
# ---------------------------------------------------------------------------
write_section "EVIDENCE SUMMARY"
echo "SUMMARY_MODE       : ${SPARSE_MODE}"
echo "SUMMARY_PASS       : ${pass_count}"
echo "SUMMARY_FAIL       : ${fail_count}"
echo ""

case "${SPARSE_MODE}" in
    FULL-CHECKOUT)
        echo "EXPECTED_BEHAVIOUR : All repository files should be present."
        echo "EXPECTED_BEHAVIOUR : CDN/, FolderA/, FolderB/ all materialised."
        echo "EXPECTED_BEHAVIOUR : All root-level files present."
        echo "PROOF_POSITIVE     : All PASS rows, zero FAIL rows."
        ;;
    SPARSE-DIRECTORIES)
        echo "EXPECTED_BEHAVIOUR : sparseCheckoutDirectories=CDN (cone mode)."
        echo "EXPECTED_BEHAVIOUR : CDN/ materialised; FolderA/ and FolderB/ absent."
        echo "EXPECTED_BEHAVIOUR : Root-level files PRESENT (cone-mode always includes root)."
        echo "CONE_MODE_NOTE     : git cone mode materialises ALL root-level tracked files."
        echo "PROOF_POSITIVE     : RootFile1.yml PRESENT + FolderA/a1.txt ABSENT."
        ;;
    SPARSE-PATTERNS)
        echo "EXPECTED_BEHAVIOUR : sparseCheckoutPatterns=CDN/** (non-cone / pattern mode)."
        echo "EXPECTED_BEHAVIOUR : Only paths matching CDN/** are materialised."
        echo "EXPECTED_BEHAVIOUR : Root-level files ABSENT (pattern mode does not include root)."
        echo "EXPECTED_BEHAVIOUR : FolderA/ and FolderB/ absent."
        echo "PROOF_POSITIVE     : RootFile1.yml ABSENT + CDN/cdnfile1.txt PRESENT."
        ;;
    SPARSE-BOTH-PATTERNS-WIN)
        echo "EXPECTED_BEHAVIOUR : BOTH sparseCheckoutDirectories=FolderA AND sparseCheckoutPatterns=CDN/** set."
        echo "EXPECTED_BEHAVIOUR : Azure DevOps uses sparseCheckoutPatterns; directories ignored."
        echo "EXPECTED_BEHAVIOUR : CDN/ materialised; FolderA/ ABSENT (proves directories ignored)."
        echo "EXPECTED_BEHAVIOUR : Root-level files ABSENT (pattern mode)."
        echo "PROOF_POSITIVE     : FolderA/a1.txt ABSENT + CDN/cdnfile1.txt PRESENT + RootFile1.yml ABSENT."
        ;;
    *)
        echo "EXPECTED_BEHAVIOUR : Unknown mode – manual inspection required."
        ;;
esac

echo ""
echo "##[section]Workspace inspection complete."
exit 0
