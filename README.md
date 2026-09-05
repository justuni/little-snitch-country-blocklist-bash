# Little Snitch Country Blocklists (Bash)

A subscription-free, Go-free bash generator for Little Snitch country blocklists.

## What is this?

`littlesnitch-country-blocklists-bash` generates Little Snitch rule group files (`.lsrules`) for blocking outbound connections to IP ranges registered to specific countries.

It uses only **bash** and standard Unix tools (`curl`, `awk`, `sort`). Data comes from the free, public RIR delegation statistics files (AFRINIC, APNIC, ARIN, LACNIC, RIPE NCC) — no API keys or paid subscriptions required.

## Prerequisites

- **Operating system:** macOS, Linux, or WSL
- **Shell:** `bash`
- **Tools:** `curl`, `awk`, and `sort` (standard on most Unix-like systems)
- **Network:** an active internet connection for the initial RIR download

`generate.sh` checks for the required tools at startup and exits with install hints if any are missing. If you need to install them manually:

```bash
# macOS (Homebrew)
brew install curl gawk coreutils

# Ubuntu / Debian
sudo apt update
sudo apt install -y curl gawk coreutils
```

## Usage

```bash
./generate.sh [OPTIONS]
```

Run with the defaults to download the latest RIR delegation files into `data/`
and write one `.lsrules` file per country to `blocklists_by_country/<CC>.lsrules`:

```bash
./generate.sh
```

Options:

- `-h`, `--help` — show help and exit
- `-d DIR`, `--data DIR` — directory for downloaded RIR files (default: `data/`)
- `-o DIR`, `--output DIR` — directory for generated `.lsrules` files (default: `blocklists_by_country/`)
- `-n`, `--no-download` — use existing RIR files; do not fetch updates

## Importing into Little Snitch

1. Run `./generate.sh`.
2. In Little Snitch, add a rule group from the generated `blocklists_by_country/<CC>.lsrules` files.

The files are standalone blocklists containing only `denied-remote-addresses` for the given country.

## Country code lookup

`generate.sh` maps ISO-3166 country codes to human-readable names using
`country-codes.tsv` in the project root. Each generated `.lsrules` file is named
`<CC>.lsrules` and uses a readable label such as:

```json
"name": "Block Germany (DE) IP ranges"
```

The mapping comes from the public-domain `/usr/share/zoneinfo/iso3166.tab`
(available on macOS and most Unix systems), with a small set of extra regional
codes the RIRs use (e.g. `AP`, `EU`, `UK`).

## Data sources

- <https://ftp.apnic.net/stats/>
- <https://www.apnic.net/manage-ip/manage-resources/rir-statistics/>
