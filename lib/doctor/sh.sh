#!/bin/sh
# doctor 适配器:sh —— 自举(doctor 自身即 sh 工程)
# Crapper: 近似圈复杂度 = 1 + if/elif/for/while/until/&&/|| 的出现次数(case 不细分,
#          嵌入 awk 的控制流也计入——它就是该函数的真实逻辑)
# Dryer: jscpd(--format bash,无扩展名文件不在其扫描面);Mutator 无:unused/quote 归 shellcheck(LSP 面)
export PATH="$PATH:$HOME/.local/bin"
EX='node_modules|\.git'
[ -n "${DOCTOR_EXCLUDE:-}" ] && EX="$EX|$DOCTOR_EXCLUDE"
export DOCTOR_EXCLUDE="$EX"
# 文件面 = *.sh + shebang 是 sh/bash 的无扩展名文件(如 bin/doctor)
FILES=$(while IFS= read -r f; do
	case "$f" in
		*.sh) printf '%s\n' "$f" ;;
		*) [ -f "$f" ] && head -1 "$f" 2>/dev/null | grep -q '^#!.*sh' && printf '%s\n' "$f" ;;
	esac
done < "${DOCTOR_FILELIST:-/dev/null}" | grep -Ev "$EX")
[ -n "$FILES" ] || FILES=$(find . -maxdepth 4 -name '*.sh' -not -path '*/.git/*' 2>/dev/null | grep -Ev "$EX" | sed 's|^\./||' || true)
[ -n "$FILES" ] || exit 3
echo "== sh (*.sh + shebang, excluded: $EX) =="

echo "── Crapper: CRAP >= 10 ──"
out=$(awk '
function kw() {
	if ($0 ~ /^[[:space:]]*(if|elif|for|while|until)([[:space:]]|\(|;|$)/) comp[cur]++
	comp[cur] += gsub(/&&/, "&&") + gsub(/\|\|/, "||")
}
FNR==1 { cur=FILENAME SUBSEP "<top>"; comp[cur]=1; fstart[cur]=1 }
# 函数边界:列 0 的 name() { 起;单行函数(name() { …; })同行闭合,多行函数到行首 } 止(容缩进,如 }'"'"' | sort)
# 顶层代码记入 <top>
/^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/ {
	fn=$1; sub(/\(\).*/, "", fn)
	cur=FILENAME SUBSEP fn; comp[cur]=1; fstart[cur]=FNR
	kw()
	if ($0 ~ /\}[[:space:]]*$/) cur=FILENAME SUBSEP "<top>"
	next
}
/^[[:space:]]*\}/ { cur=FILENAME SUBSEP "<top>"; next }
{ kw() }
END { for (f in comp) { n=split(f, p, SUBSEP); print p[2], comp[f], p[1] ":" fstart[f] } }
' $FILES | awk '
BEGIN { fx=ENVIRON["DOCTOR_FUNCS_EX"]; m=split(fx, L, "\n"); for (i=1;i<=m;i++) { split(L[i], kv, "::"); fp[i]=kv[1]; fn[i]=kv[2] } }
{ skip=0; for (i=1;i<=m;i++) if ($3 ~ fp[i] && $1 ~ fn[i]) { skip=1; break }
  if (!skip && $2+0>=10) printf "  %-22s %6.1f %4d %-6s (%s)\n", $1, $2, $2, "--", $3 }' | sort -k2 -rn)
[ -n "$out" ] && { printf "  %-22s %6s %4s %-6s %s\n" Function CRAP Comp Cov Path; echo "$out"; } || echo "  (none)"

echo "── Dryer: repeated blocks (jscpd >=64 tokens) ──"
if command -v jscpd >/dev/null; then
	. "$(dirname "$0")/common.sh"
	PT=$(mktemp -d) && TAB=$(printf '\t') && printf '%s\n' "$FILES" > "$PT/members"
	jscpd_scan "$PT" bash
	if [ -s "$PT/pairs" ]; then
		while IFS="$TAB" read -r idx fa fb tok; do cat "$PT/b.$idx"; echo; done < "$PT/pairs"
	else
		echo "  (none)"
	fi
	rm -rf "$PT"
else
	echo "  missing jscpd: npm i -g jscpd"
fi
exit 0
