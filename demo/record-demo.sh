#!/bin/bash
set -e
G=$'\033[0;32m' R=$'\033[0;31m' Y=$'\033[0;33m' B=$'\033[1m' D=$'\033[2m' Z=$'\033[0m' C=$'\033[0;36m'

type_cmd() {
  printf "${D}\$ ${Z}"
  for ((i=0; i<${#1}; i++)); do printf "%s" "${1:$i:1}"; sleep 0.03; done
  echo ""
}

clear
echo ""
echo "  ${B}Night Shift${Z} ${D}v1.0${Z}"
echo "  ${D}Your codebase improves while you sleep${Z}"
echo ""
sleep 1

type_cmd "nightshift run --repos ~/projects/*"
sleep 0.5

echo ""
echo "  ${C}02:00${Z}  Starting nightly scan across ${B}4 repositories${Z}"
echo ""
sleep 0.5

echo "  ${B}Scanning:${Z} golf-club-community"
sleep 0.3
echo "  ${Y}!${Z} 3 ESLint errors  ${D}(unused imports)${Z}"
echo "  ${Y}!${Z} 1 TypeScript strict violation"
echo "  ${G}+${Z} Auto-fixed, committed to ${D}fix/nightshift-lint-0808${Z}"
sleep 0.6

echo ""
echo "  ${B}Scanning:${Z} auth-provider"
sleep 0.3
echo "  ${R}!${Z} 1 security issue  ${D}(missing rate limiter on /api/token)${Z}"
echo "  ${G}+${Z} Patch created on ${D}fix/nightshift-security-0808${Z}"
sleep 0.6

echo ""
echo "  ${B}Scanning:${Z} sales-hub"
sleep 0.3
echo "  ${G}OK${Z}  No issues found"
sleep 0.4

echo ""
echo "  ${B}Scanning:${Z} golfschul-app"
sleep 0.3
echo "  ${Y}!${Z} 2 documentation gaps  ${D}(missing JSDoc on public API)${Z}"
echo "  ${G}+${Z} Docs added, committed to ${D}fix/nightshift-docs-0808${Z}"
sleep 0.6

echo ""
echo "  ${C}02:14${Z}  ${B}Nightly complete${Z}"
echo ""
echo "  ${B}4${Z} repos scanned  |  ${Y}7${Z} issues found  |  ${G}6${Z} auto-fixed  |  ${R}1${Z} needs review"
echo ""
echo "  ${D}Morning summary sent.${Z}"
echo ""
sleep 3
