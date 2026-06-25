#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
artifact_name="x-gateway"

usage() {
  cat <<EOF
Usage:
  scripts/render-homebrew-formula.sh <version> <reader|writer> [output-file]

Reads archive checksums from:
  dist/homebrew/$artifact_name-<version>-<target>.tar.gz.sha256

Environment:
  RELEASE_DIR       Directory containing archives and .sha256 files.
  RELEASE_BASE_URL  Release URL base. Defaults to GitHub v<version>.

Example:
  scripts/build-homebrew-release.sh darwin-arm64 darwin-x64
  scripts/render-homebrew-formula.sh 0.1.3 reader Formula/x-gateway-reader.rb
  scripts/render-homebrew-formula.sh 0.1.3 writer Formula/x-gateway-writer.rb

This renderer expects Swift macOS release archives. Linux archives are
unsupported until the project defines a reviewed Swift Linux build contract.
Each archive must contain x-gateway-reader and x-gateway-writer.
EOF
}

sha_for_target() {
  local version target release_dir sha_file
  version="$1"
  target="$2"
  release_dir="$3"
  sha_file="$release_dir/$artifact_name-$version-$target.tar.gz.sha256"

  if [[ ! -f "$sha_file" ]]; then
    printf 'missing checksum file: %s\n' "$sha_file" >&2
    return 1
  fi

  awk '{print $1}' "$sha_file"
}

validate_version() {
  local version
  version="$1"

  if [[ "$version" == *..* || ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z][0-9A-Za-z.+-]*)?$ ]]; then
    printf 'unsafe release version: %s\n' "$version" >&2
    printf 'expected archive-safe semver-like value without path separators or parent traversal\n' >&2
    return 1
  fi
}

validate_sha256() {
  local target sha
  target="$1"
  sha="$2"

  if [[ ! "$sha" =~ ^[0-9a-fA-F]{64}$ ]]; then
    printf 'invalid sha256 for %s: %s\n' "$target" "$sha" >&2
    return 1
  fi
}

validate_release_base_url() {
  local release_base_url
  release_base_url="$1"

  if [[ "$release_base_url" != https://* ]]; then
    printf 'unsafe release base URL: %s\n' "$release_base_url" >&2
    printf 'expected an https URL suitable for a Homebrew formula string\n' >&2
    return 1
  fi

  if [[ "$release_base_url" == *$'\n'* ||
        "$release_base_url" == *$'\r'* ||
        "$release_base_url" == *$'\t'* ||
        "$release_base_url" == *' '* ||
        "$release_base_url" == *'"'* ||
        "$release_base_url" == *'\'* ||
        "$release_base_url" == *'#{'* ]]; then
    printf 'unsafe release base URL: %s\n' "$release_base_url" >&2
    printf 'release base URL must not contain whitespace, quotes, backslashes, control characters, or Ruby interpolation markers\n' >&2
    return 1
  fi
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    return
  fi
  if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
    usage
    return 2
  fi

  local version output variant release_dir release_base_url
  version="$1"
  variant="$2"
  output="${3:-$repo_root/Formula/$artifact_name-$variant.rb}"
  release_dir="${RELEASE_DIR:-$repo_root/dist/homebrew}"
  release_base_url="${RELEASE_BASE_URL:-https://github.com/tacogips/x-gateway/releases/download/v$version}"

  validate_version "$version"
  validate_release_base_url "$release_base_url"

  case "$variant" in
    reader | writer) ;;
    *)
      printf 'unsupported formula variant: %s\n' "$variant" >&2
      printf 'expected one of: reader, writer\n' >&2
      return 2
      ;;
  esac

  local darwin_arm64_sha darwin_x64_sha
  darwin_arm64_sha="$(sha_for_target "$version" darwin-arm64 "$release_dir")"
  darwin_x64_sha="$(sha_for_target "$version" darwin-x64 "$release_dir")"
  validate_sha256 darwin-arm64 "$darwin_arm64_sha"
  validate_sha256 darwin-x64 "$darwin_x64_sha"

  local class_name desc install_body test_body
  case "$variant" in
    reader)
      class_name="XGatewayReader"
      desc="Read-only X API gateway CLI"
      install_body='    bin.install "bin/x-gateway-reader"'
      test_body="    assert_match \"$version\", shell_output(\"#{bin}/x-gateway-reader version\")"
      ;;
    writer)
      class_name="XGatewayWriter"
      desc="Write-capable X API gateway CLI"
      install_body='    bin.install "bin/x-gateway-writer"'
      test_body="    assert_match \"$version\", shell_output(\"#{bin}/x-gateway-writer version\")"
      ;;
  esac

  mkdir -p "$(dirname "$output")"
  cat > "$output" <<EOF
class $class_name < Formula
  desc "$desc"
  homepage "https://github.com/tacogips/x-gateway"
  version "$version"
  license "MIT"

  livecheck do
    url :stable
    strategy :github_latest
  end

  on_macos do
    if Hardware::CPU.arm?
      url "$release_base_url/$artifact_name-$version-darwin-arm64.tar.gz"
      sha256 "$darwin_arm64_sha"
    else
      url "$release_base_url/$artifact_name-$version-darwin-x64.tar.gz"
      sha256 "$darwin_x64_sha"
    end
  end

  def install
$install_body
  end

  test do
$test_body
  end
end
EOF

  printf 'rendered %s\n' "$output"
}

main "$@"
