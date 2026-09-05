#!/usr/bin/env bash
#
# generate.sh
#
# Build Little Snitch country blocklists (.lsrules) from public RIR data.
#
# Downloads the latest delegation statistics from AFRINIC, APNIC, ARIN,
# LACNIC, and RIPE NCC, then converts IPv4/IPv6 allocations into one
# 'denied-remote-addresses' blocklist per country.
#
# Output: blocklists_by_country/<CC>.lsrules
# Requirements: bash, curl, awk, sort
# Usage: ./generate.sh [OPTIONS]
#

set -euo pipefail

check_tool() {
  local name="$1"
  local hint="$2"
  if ! command -v "${name}" >/dev/null 2>&1; then
    printf 'Error: required tool "%s" not found in PATH.\n' "${name}" >&2
    printf '  Install hint: %s\n' "${hint}" >&2
    return 1
  fi
}

missing=0
check_tool curl "brew install curl   (or apt install curl)" || missing=1
check_tool awk  "brew install gawk   (or apt install gawk / mawk)" || missing=1
check_tool sort "brew install coreutils   (or apt install coreutils)" || missing=1

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODES_FILE="${SCRIPT_DIR}/country-codes.tsv"

DEFAULT_DATA_DIR="${SCRIPT_DIR}/data"
DEFAULT_OUT_DIR="${SCRIPT_DIR}/blocklists_by_country"
DATA_DIR=""
OUT_DIR=""
NO_DOWNLOAD=0

usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS]

Generate Little Snitch country blocklists (.lsrules) from public RIR data.

Options:
  -h, --help          Show this help message and exit
  -d, --data DIR      Directory for downloaded RIR files (default: ${DEFAULT_DATA_DIR})
  -o, --output DIR    Directory for generated .lsrules files (default: ${DEFAULT_OUT_DIR})
  -n, --no-download   Use existing RIR files; do not fetch updates
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -d|--data)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        printf 'Error: %s requires a directory argument.\n' "$1" >&2
        exit 1
      fi
      DATA_DIR="$2"
      shift 2
      ;;
    -o|--output)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        printf 'Error: %s requires a directory argument.\n' "$1" >&2
        exit 1
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    -n|--no-download)
      NO_DOWNLOAD=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'Error: unknown option %s\n' "$1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

DATA_DIR="${DATA_DIR:-${DEFAULT_DATA_DIR}}"
OUT_DIR="${OUT_DIR:-${DEFAULT_OUT_DIR}}"

if [[ -f "${CODES_FILE}" ]]; then
  CODES_ARGS=("${CODES_FILE}")
  HAVE_CODES=1
else
  printf 'Warning: country code mapping not found at %s; using codes only.\n' "${CODES_FILE}" >&2
  CODES_ARGS=()
  HAVE_CODES=0
fi

RIRS=(afrinic apnic arin lacnic ripencc)

printf '==> Generating Little Snitch country blocklists...\n' >&2

mkdir -p "${DATA_DIR}" "${OUT_DIR}"

fetch_rir() {
  local rir="$1"
  local file url

  case "${rir}" in
    afrinic)
      file="delegated-afrinic-extended-latest"
      url="https://ftp.afrinic.net/stats/afrinic/${file}"
      ;;
    apnic)
      file="delegated-apnic-extended-latest"
      url="https://ftp.apnic.net/stats/apnic/${file}"
      ;;
    arin)
      file="delegated-arin-extended-latest"
      url="https://ftp.arin.net/pub/stats/arin/${file}"
      ;;
    lacnic)
      file="delegated-lacnic-extended-latest"
      url="https://ftp.lacnic.net/pub/stats/lacnic/${file}"
      ;;
    ripencc)
      file="delegated-ripencc-extended-latest"
      url="https://ftp.ripe.net/pub/stats/ripencc/${file}"
      ;;
    *)
      printf 'Error: unknown RIR %s\n' "${rir}" >&2
      exit 1
      ;;
  esac

  local dest="${DATA_DIR}/${file}"

  if [[ -f "${dest}" ]]; then
    curl -fsSL --remote-time -z "${dest}" -o "${dest}" "${url}" || true
  else
    curl -fsSL --remote-time -o "${dest}" "${url}"
  fi
  printf '  ok: %s\n' "${file}" >&2
}

if [[ "${NO_DOWNLOAD}" -eq 1 ]]; then
  printf '==> Skipping downloads; using existing files in %s\n' "${DATA_DIR}" >&2
else
  printf '==> Downloading/updating RIR delegation files...\n' >&2
  for rir in "${RIRS[@]}"; do
    fetch_rir "${rir}"
  done
fi

rm -f "${OUT_DIR}"/*.lsrules

today=$(date -u +%Y-%m-%d)

shopt -s nullglob
files=("${DATA_DIR}"/delegated-*-latest)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No RIR delegation files found in ${DATA_DIR}" >&2
  exit 1
fi

printf '==> Parsing allocations and building .lsrules files...\n' >&2

cat "${files[@]}" | awk -F'|' '
function ip_to_int(ip, a, n) {
  n = split(ip, a, ".")
  return a[1]*16777216 + a[2]*65536 + a[3]*256 + a[4]
}
function int_to_ip(n, o1, o2, o3, o4) {
  o1 = int(n/16777216)
  o2 = int((n%16777216)/65536)
  o3 = int((n%65536)/256)
  o4 = n%256
  return o1 "." o2 "." o3 "." o4
}
NF < 7 { next }
$1 ~ /^(#|version|summary|registry)/ { next }
$3 != "ipv4" && $3 != "ipv6" { next }
$2 == "*" || $2 == "" { next }
$7 == "reserved" || $7 == "available" { next }
{
  cc = $2
  if ($3 == "ipv4") {
    start = $4
    count = $5 + 0
    if (count <= 0) next
    n = ip_to_int(start)
    last = int_to_ip(n + count - 1)
    printf "%s\t%s-%s\n", cc, start, last
  } else {
    printf "%s\t%s/%s\n", cc, $4, $5
  }
}' | LC_ALL=C sort -t$'\t' -k1,1 -k2,2 | uniq | awk -F'\t' -v outdir="${OUT_DIR}" -v today="${today}" -v have_codes="${HAVE_CODES}" '
function json_escape(s, t) {
  t = s
  gsub(/\\/, "\\\\", t)
  gsub(/"/, "\\\"", t)
  return t
}
function country_label(cc) {
  if (have_codes && (cc in names) && names[cc] != "") {
    return json_escape(names[cc] " (" cc ")")
  }
  return json_escape(cc)
}
function close_group(out) {
  if (out != "") {
    print "\n  ]" >> out
    print "}" >> out
    close(out)
  }
}
BEGIN { prev = ""; out = "" }
FNR == NR && have_codes {
  if (NF >= 2 && $1 !~ /^#/) {
    names[$1] = $2
  }
  next
}
{
  cc = $1
  range = $2
  if (cc != prev) {
    close_group(out)
    prev = cc
    out = outdir "/" cc ".lsrules"
    first = 1
    label = country_label(cc)
    printf "{\n" > out
    printf "  \"name\": \"Block %s IP ranges\",\n", label > out
    printf "  \"description\": \"Deny outbound connections to IP ranges registered to %s (Source: public RIR delegation data, %s).\",\n", label, today > out
    printf "  \"denied-remote-addresses\": [" > out
  }
  if (!first) printf ",\n" >> out
  printf "    \"%s\"", range >> out
  first = 0
}
END { close_group(out) }
' "${CODES_ARGS[@]}" -

count=$(find "${OUT_DIR}" -maxdepth 1 -name '*.lsrules' -type f | wc -l | tr -d '[:space:]')
printf '==> Done. Wrote %s country blocklists to %s\n' "${count}" "${OUT_DIR}" >&2
