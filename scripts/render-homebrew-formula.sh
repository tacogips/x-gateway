#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
artifact_name="x-gateway"
products=("x-gateway-read" "x-gateway-write")

usage() {
  cat <<EOF
Usage:
  scripts/render-homebrew-formula.sh <version> [output-file] [combined|read|write]

Reads archive checksums from:
  dist/homebrew/$artifact_name-<version>-<target>.tar.gz.sha256

Environment:
  RELEASE_DIR       Directory containing archives and .sha256 files.
  RELEASE_BASE_URL  Release URL base. Defaults to GitHub v<version>.

Example:
  scripts/build-homebrew-release.sh darwin-arm64 darwin-x64
  scripts/render-homebrew-formula.sh 0.1.1 Formula/$artifact_name.rb
  scripts/render-homebrew-formula.sh 0.1.1 Formula/x-gateway-read.rb read
  scripts/render-homebrew-formula.sh 0.1.1 Formula/x-gateway-write.rb write

This renderer expects Swift macOS release archives. Linux archives are
unsupported until the project defines a reviewed Swift Linux build contract.
Each archive must contain x-gateway-read and x-gateway-write.
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

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    return
  fi
  if [[ "${1:-}" == "" ]]; then
    usage
    return 2
  fi

  local version output variant release_dir release_base_url
  version="$1"
  output="${2:-$repo_root/Formula/$artifact_name.rb}"
  variant="${3:-combined}"
  release_dir="${RELEASE_DIR:-$repo_root/dist/homebrew}"
  release_base_url="${RELEASE_BASE_URL:-https://github.com/tacogips/x-gateway/releases/download/v$version}"

  case "$variant" in
    combined | read | write) ;;
    *)
      printf 'unsupported formula variant: %s\n' "$variant" >&2
      printf 'expected one of: combined, read, write\n' >&2
      return 2
      ;;
  esac

  local darwin_arm64_sha darwin_x64_sha
  darwin_arm64_sha="$(sha_for_target "$version" darwin-arm64 "$release_dir")"
  darwin_x64_sha="$(sha_for_target "$version" darwin-x64 "$release_dir")"

  local class_name desc install_body test_body
  case "$variant" in
    combined)
      class_name="XGateway"
      desc="X API client and gateway CLI"
      install_body='    bin.install "bin/x-gateway-read"
    bin.install "bin/x-gateway-write"'
      test_body="    assert_match \"$version\", shell_output(\"#{bin}/x-gateway-read version\")
    assert_match \"$version\", shell_output(\"#{bin}/x-gateway-write version\")"
      ;;
    read)
      class_name="XGatewayRead"
      desc="Read-only X API gateway CLI"
      install_body='    bin.install "bin/x-gateway-read"'
      test_body="    assert_match \"$version\", shell_output(\"#{bin}/x-gateway-read version\")"
      ;;
    write)
      class_name="XGatewayWrite"
      desc="Write-capable X API gateway CLI"
      install_body='    bin.install "bin/x-gateway-write"'
      test_body="    assert_match \"$version\", shell_output(\"#{bin}/x-gateway-write version\")"
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
