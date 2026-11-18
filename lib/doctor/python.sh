#!/bin/sh
# doctor 适配器:Python —— radon(复杂度→CRAP) / jscpd(重复) / vulture(死代码)
export PATH="$PATH:$HOME/.local/bin"
# 排除:默认第三方/虚拟环境/构建产物,.doctorignore 叠加(DOCTOR_EXCLUDE)
EX='venv|\.venv|\.tox|site-packages|3rd|vendor|node_modules|\.git|__pycache__|build|dist'
[ -n "${DOCTOR_EXCLUDE:-}" ] && EX="$EX|$DOCTOR_EXCLUDE"
export DOCTOR_EXCLUDE="$EX"
FILES=$(grep '\.py$' "${DOCTOR_FILELIST:-/dev/null}" 2>/dev/null | grep -Ev "$EX")
[ -n "$FILES" ] || FILES=$(find . -maxdepth 6 -name '*.py' -not -path '*/.*' 2>/dev/null | grep -Ev "$EX" | sed 's|^\./||' || true)
[ -n "$FILES" ] || exit 3
echo "== Python (excluded: $EX) =="

echo "── Crapper: CRAP >= 10 ──"
if command -v radon >/dev/null; then
	# radon JSON → "名字 分支 路径:行",再套 Go/Lua 同款表格与函数级过滤
	out=$(radon cc -j $FILES 2>/dev/null | python3 -c '
import json, sys
for f, blocks in json.load(sys.stdin).items():
    for b in blocks:
        print(b["name"], b["complexity"], "%s:%s" % (f, b.get("lineno", 0)))
' | awk '
	BEGIN { fx=ENVIRON["DOCTOR_FUNCS_EX"]; m=split(fx, L, "\n"); for (i=1;i<=m;i++) { split(L[i], kv, "::"); fp[i]=kv[1]; fn[i]=kv[2] } }
	{ skip=0; for (i=1;i<=m;i++) if ($3 ~ fp[i] && $1 ~ fn[i]) { skip=1; break }
	  if (!skip && $2+0>=10) printf "  %-22s %6.1f %4d %-6s (%s)\n", $1, $2, $2, "--", $3 }' | sort -k2 -rn)
	[ -n "$out" ] && { printf "  %-22s %6s %4s %-6s %s\n" Function CRAP Comp Cov Path; echo "$out"; } || echo "  (none)"
else
	echo "  missing radon: pipx install radon"
fi

echo "── Dryer: repeated blocks (jscpd >=64 tokens) ──"
if command -v jscpd >/dev/null; then
	. "$(dirname "$0")/common.sh"
	PT=$(mktemp -d) && TAB=$(printf '\t') && printf '%s\n' "$FILES" > "$PT/members"
	jscpd_scan "$PT" python
	if [ -s "$PT/pairs" ]; then
		while IFS="$TAB" read -r idx fa fb tok; do cat "$PT/b.$idx"; echo; done < "$PT/pairs"
	else
		echo "  (none)"
	fi
	rm -rf "$PT"
else
	echo "  missing jscpd: npm i -g jscpd"
fi

echo "── Mutator: dead code (vulture) ──"
if command -v vulture >/dev/null; then
	out=$(vulture $FILES 2>/dev/null | head -30)
	[ -n "$out" ] && echo "$out" || echo "  (none)"
else
	echo "  missing vulture: pipx install vulture"
fi
exit 0
