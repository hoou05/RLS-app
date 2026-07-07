#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Download SHHS files from NSRR into a local, gitignored data directory.

Usage:
  tools/download_shhs.sh [datasets|polysomnography|edfs-shhs1|edfs-shhs2|all] [download_root]

Defaults:
  subset        datasets
  download_root data/nsrr

Requirements:
  - Approved SHHS access on sleepdata.org.
  - Ruby and the NSRR gem. On Ruby 2.6, install the last compatible release:
      gem install nsrr -v 5.0.0 --user-install --no-document
    On Ruby 2.7.2+, the latest release is fine:
      gem install nsrr --no-document
  - NSRR download token from https://sleepdata.org/token.

Token handling:
  The NSRR gem normally prompts for the token interactively. If NSRR_TOKEN is set,
  this script passes it with --token so the download can run non-interactively.
  NSSR_TOKEN is also accepted for compatibility with local .env typos.

Examples:
  tools/download_shhs.sh datasets
  NSRR_TOKEN='...' tools/download_shhs.sh datasets /Volumes/research/nsrr
  tools/download_shhs.sh edfs-shhs1 /Volumes/research/nsrr
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

subset="${1:-datasets}"
download_root="${2:-data/nsrr}"

case "$subset" in
  datasets) nsrr_path="shhs/datasets" ;;
  polysomnography) nsrr_path="shhs/polysomnography" ;;
  edfs-shhs1) nsrr_path="shhs/polysomnography/edfs/shhs1" ;;
  edfs-shhs2) nsrr_path="shhs/polysomnography/edfs/shhs2" ;;
  all) nsrr_path="shhs" ;;
  *)
    echo "Unknown subset: $subset" >&2
    usage >&2
    exit 2
    ;;
esac

if ! command -v ruby >/dev/null 2>&1; then
  echo "Ruby is required before installing the NSRR gem." >&2
  exit 1
fi

gem_user_bin="$(ruby -e 'print Gem.bindir(Gem.user_dir)' 2>/dev/null || true)"
if [[ -n "$gem_user_bin" && -d "$gem_user_bin" ]]; then
  PATH="$gem_user_bin:$PATH"
fi

if ! command -v nsrr >/dev/null 2>&1; then
  ruby_27_ok="$(ruby -e 'exit(Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7.2") ? 0 : 1)' && echo yes || echo no)"
  if [[ "$ruby_27_ok" == "yes" ]]; then
    echo "NSRR gem is not installed. Run: gem install nsrr --no-document" >&2
  else
    echo "NSRR gem is not installed. Ruby is $(ruby -v)." >&2
    echo "Run: gem install nsrr -v 5.0.0 --user-install --no-document" >&2
    echo "Then ensure RubyGems' user bin directory is on PATH." >&2
  fi
  exit 1
fi

token="${NSRR_TOKEN:-${NSSR_TOKEN:-}}"
if [[ -z "$token" && -f ".env" ]]; then
  while IFS='=' read -r key value || [[ -n "${key:-}${value:-}" ]]; do
    case "$key" in
      NSRR_TOKEN|NSSR_TOKEN)
        value="${value%$'\r'}"
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        token="$value"
        ;;
    esac
  done <".env"
fi

mkdir -p "$download_root"
cd "$download_root"

echo "Downloading $nsrr_path into $(pwd)"
echo "Press Ctrl-C to pause; rerun the same command to resume."

if [[ -n "$token" ]]; then
  dataset_slug="${nsrr_path%%/*}"
  if [[ "$nsrr_path" == */* ]]; then
    dataset_path="${nsrr_path#*/}"
  else
    dataset_path=""
  fi
  NSRR_TOKEN="$token" ruby -rnsrr -rnsrr/models/all -e '
    dataset = Nsrr::Models::Dataset.find(ARGV.fetch(0), ENV.fetch("NSRR_TOKEN"))
    abort("Dataset not found or token is not authorized for this dataset.") unless dataset
    dataset.download(ARGV.fetch(1), method: "fast", depth: "recursive")
  ' "$dataset_slug" "$dataset_path"
else
  nsrr download "$nsrr_path" --fast
fi
