#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

REPO_BASE="naxcivan-goyercin-platform"
DESCRIPTION="Naxcivan pigeon community, marketplace and veterinary services website"
BRANCH="main"

say() { printf '\n\033[1;36m[NG-PUBLISH]\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31m[XƏTA]\033[0m %s\n' "$*" >&2; exit 1; }

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SITE_DIR="$ROOT/site"

[[ -f "$SITE_DIR/index.html" ]] || die "site/index.html tapılmadı. ZIP paketini tam çıxarın."
[[ -f "$SITE_DIR/manifest.webmanifest" ]] || die "PWA manifest faylı tapılmadı."
[[ -f "$SITE_DIR/sw.js" ]] || die "Service Worker faylı tapılmadı."
[[ -f "$ROOT/.github/workflows/pages.yml" ]] || die "GitHub Pages workflow faylı tapılmadı."

if ! command -v git >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1; then
  command -v pkg >/dev/null 2>&1 || die "Bu skript Termux daxilində işlədilməlidir."
  say "Git və GitHub CLI quraşdırılır..."
  pkg update -y
  pkg install -y git gh
fi

command -v python >/dev/null 2>&1 || {
  say "Python quraşdırılır (lokal yoxlama üçün)..."
  pkg install -y python
}

say "HTML/JSON faylları yoxlanılır..."
python - "$SITE_DIR" <<'PY'
import json, pathlib, re, sys
p = pathlib.Path(sys.argv[1])
json.loads((p / "manifest.webmanifest").read_text(encoding="utf-8"))
html = (p / "index.html").read_text(encoding="utf-8")
if not re.search(r"<!doctype\s+html", html[:300], re.I):
    raise SystemExit("index.html HTML5 sənədi kimi görünmür.")
if "navigator.serviceWorker.register" not in html:
    raise SystemExit("Service Worker qeydiyyatı index.html daxilində tapılmadı.")
print("HTML əsas yoxlaması və manifest JSON yoxlaması uğurludur.")
PY

say "GitHub hesabına giriş yoxlanılır..."
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  say "GitHub giriş səhifəsi açılacaq. Ekrandakı kodu öz GitHub hesabında təsdiqlə."
  gh auth login --hostname github.com --git-protocol https --web
fi

# Workflow faylını push edə bilmək üçün tələb olunan dar OAuth scope-ları.
gh auth refresh --hostname github.com --scopes repo,workflow

OWNER="$(gh api user --jq .login)"
[[ -n "$OWNER" ]] || die "GitHub istifadəçi adı müəyyən edilmədi."

REPO="$REPO_BASE"
n=1
while gh repo view "$OWNER/$REPO" >/dev/null 2>&1; do
  n=$((n + 1))
  REPO="${REPO_BASE}-${n}"
done
FULL="$OWNER/$REPO"

say "Yeni public repository yaradılır: $FULL"
gh repo create "$REPO" --public --description "$DESCRIPTION"

cd "$ROOT"
if [[ -d .git ]]; then
  die "Paket qovluğunda artıq .git var. Təmiz ZIP-dən çıxarılan qovluqdan başladın."
fi

git init --initial-branch="$BRANCH"
git config user.name "$OWNER"
NO_REPLY="$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
git config user.email "$NO_REPLY"
git add .
git commit -m "Initial release: Naxcivan Goyercin website"
git remote add origin "https://github.com/$FULL.git"

say "GitHub Pages GitHub Actions rejimində aktivləşdirilir..."
if gh api "repos/$FULL/pages" >/dev/null 2>&1; then
  gh api --method PUT "repos/$FULL/pages" -f build_type=workflow >/dev/null
else
  gh api --method POST "repos/$FULL/pages" -f build_type=workflow >/dev/null
fi

say "Sayt GitHub-a göndərilir..."
git push --set-upstream origin "$BRANCH"

say "GitHub Pages iş axınının başlaması gözlənilir..."
sleep 8
RUN_ID="$(gh run list --repo "$FULL" --workflow pages.yml --branch "$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null || true)"
if [[ -n "$RUN_ID" ]]; then
  gh run watch "$RUN_ID" --repo "$FULL" --exit-status || {
    say "Workflow uğursuz oldu. Loglara baxmaq üçün: gh run list --repo $FULL"
    exit 2
  }
else
  say "Workflow hələ görünmür; GitHub Actions bir neçə dəqiqəyə başlaya bilər."
fi

PAGES_URL="https://${OWNER}.github.io/${REPO}/"
say "YAYIM TAMAMLANDI"
printf '\nRepository: https://github.com/%s\nWebsite:    %s\n' "$FULL" "$PAGES_URL"
printf '\nQeyd: GitHub Pages ilk dəfə aktivləşərkən DNS/HTTPS yayımı bir neçə dəqiqə çəkə bilər.\n'
