#!/bin/sh
# doctor 适配器:Lua —— 只查当前工程:排除第三方(默认 3rd|vendor|node_modules,可用 DOCTOR_EXCLUDE 覆盖)
# Crapper: luacheck W561(分支>10) / Dryer: jscpd(多态/镜像自动归组);Mutator 无:LSP 级的 unused 提示不归工程审计管
export PATH="$PATH:$HOME/.local/bin"
EX='3rd|vendor|node_modules|\.git'
[ -n "${DOCTOR_EXCLUDE:-}" ] && EX="$EX|$DOCTOR_EXCLUDE"
export DOCTOR_EXCLUDE="$EX"
FILES=$(grep '\.lua$' "${DOCTOR_FILELIST:-/dev/null}" 2>/dev/null | grep -Ev "$EX")
[ -n "$FILES" ] || FILES=$(find . -maxdepth 4 -name '*.lua' -not -path '*/.opencode/*' 2>/dev/null | grep -Ev "$EX" | sed 's|^\./||' || true)
# 门禁:整仓没有 lua 就不认这个工程;范围收窄只能发生在门内
[ -n "$FILES" ] || exit 3
# 范围与 Go 适配器对齐：显式 diff 只看改动；auto 有改动看改动，无改动仍扫全仓
scope=${DOCTOR_SCOPE:-auto}
if [ "$scope" = auto ]; then
	if [ -n "$( { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | grep -vE '(^|/)\.' | head -1 )" ]; then
		scope=diff
	else
		scope=all
	fi
fi
if [ "$scope" = diff ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	changed=$( { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | grep '\.lua$' | grep -Ev "$EX" | grep -vE '(^|/)\.' | sort -u)
	if [ -n "$changed" ]; then
		FILES=$(printf '%s\n' "$changed" | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
	else
		echo "== Lua (*.lua, excluded: $EX) =="
		echo "  (none)"
		exit 0
	fi
fi
echo "== Lua (*.lua, excluded: $EX) =="

echo "── Crapper: CRAP >= 10 ──"
if command -v luacheck >/dev/null; then
	# luacheck 行:path:line:col: (W561) cyclomatic complexity of [function|method] '名' is too high (12 > 10)
	# 括号里第一个数字 = 分支数(= gocyclo 的 comp);元表方法报 method '名',匿名函数无 '名' 段
	out=$(luacheck --no-color --codes --max-cyclomatic-complexity 10 $FILES 2>/dev/null | grep W561 | awk '
	BEGIN { fx=ENVIRON["DOCTOR_FUNCS_EX"]; m=split(fx, L, "\n"); for (i=1;i<=m;i++) { split(L[i], kv, "::"); fp[i]=kv[1]; fn[i]=kv[2] } }
	{
	  path=$1; sub(/:[0-9]+:$/,"",path)
	  comp=0; name="<anonymous>"
	  if (match($0, / is too high \([0-9]+/)) {
	    s=substr($0, RSTART, RLENGTH); comp=s; sub(/^.*\(/, "", comp)
	  }
	  if (match($0, /(function|method) \047[^\047]*\047/)) {
	    name=substr($0, RSTART, RLENGTH); sub(/^(function|method) \047/, "", name); sub(/\047$/, "", name)
	  }
	  skip=0; for (i=1;i<=m;i++) if (path ~ fp[i] && name ~ fn[i]) { skip=1; break }
	  if (comp+0>10 && !skip) printf "  %-22s %6.1f %4d %-6s (%s)\n", name, comp, comp, "--", path
	}' | sort -k2 -rn)
	[ -n "$out" ] && { printf "  %-22s %6s %4s %-6s %s\n" Function CRAP Comp Cov Path; echo "$out"; } || echo "  (none)"
else
	echo "  missing luacheck: luarocks install luacheck"
fi

# ── Dryer 管道:jscpd_scan(common.sh,克隆对·成员·排除·排序)→ classify(多态/镜像归组)→ report(渲染)──
. "$(dirname "$0")/common.sh"

# 多态启发式:两侧文件 require 了同一个低频模块 → 疑似继承/模板副本,归组;
# 被 >20 文件 require 的算基础设施(log/znet 之类),不参与判别;
# 镜像:去掉顶层目录(game/simulate/share/...)后路径相同 → 跨树同步副本;
# require 正则不用 \x27 转义:grep/sed 的括号表达式内不处理它,会变成字面
# {",\,x,2,7} 五字符——含 x/2/7 的模块名被截断(extend→e),基建统计失真
dryer_classify() {
	REQRE=$(printf 'require\\s*["\047.][^\047]*')
	REQSED=$(printf 's/require\\s*["\047]//;s/["\047]//')
	reqs() { grep -o "$REQRE" "$1" 2>/dev/null | sed "$REQSED" | sort -u; }
	printf '%s\n' "$FILES" | xargs -r -d '\n' grep -hs -o "$REQRE" \
		| sed "$REQSED" | sort | uniq -c | awk '$1>20 {print $2}' > "$T/infra"
	: > "$T/plain"; : > "$T/tpoly"; : > "$T/tmirror"
	while IFS="$TAB" read -r idx fa fb tok; do
		common=""
		if [ "$fa" != "$fb" ]; then
			reqs "$fa" > "$T/ra"; reqs "$fb" > "$T/rb"
			common=$(comm -12 "$T/ra" "$T/rb" | grep -vxFf "$T/infra" | paste -sd' ' -)
		fi
		ma=${fa#*/}; mb=${fb#*/}
		if [ -n "$common" ]; then
			printf '%s\t%s\t%s\t%s\n' "$tok" "$fa" "$fb" "$common" >> "$T/tpoly"
		elif [ -n "$ma" ] && [ "$ma" = "$mb" ]; then
			printf '%s\t%s\t%s\t%s\n' "$tok" "$fa" "$fb" "$ma" >> "$T/tmirror"
		else
			printf '%s\t%s\n' "$idx" "$tok" >> "$T/plain"
		fi
	done < "$T/pairs"
}

dryer_report() {
	if [ -s "$T/plain" ]; then
		while IFS="$TAB" read -r idx tok; do cat "$T/b.$idx"; echo; done < "$T/plain"
	else
		echo "  (none)"
	fi
	show_group() {
		[ -s "$1" ] || return 0
		echo "  $2: $(wc -l < "$1") pairs (intentional? suppress with a dryer: line in .doctorignore)"
		sort -t"$TAB" -k1,1rn "$1" | awk -F'\t' '
		{ split($4, M, " "); fam=M[1]
		  if (!(fam in seen)) { order[++n]=fam; seen[fam]=1 }
		  cnt[fam]++; pr[fam, cnt[fam]]=$2 " ↔ " $3 " (" $1 " tokens)" }
		END { for (i=1;i<=n;i++) { f=order[i]
		  printf "  · %s — %d pairs:\n", f, cnt[f]
		  for (j=1;j<=cnt[f];j++) printf "      %s\n", pr[f, j] } }'
	}
	if [ "${DOCTOR_DRYER_POLY:-}" = off ]; then
		[ -s "$T/tpoly" ] && echo "  ▽ suspected polymorphism: $(wc -l < "$T/tpoly") pairs (dryer-poly off, collapsed)"
	else
		show_group "$T/tpoly"   "▽ suspected polymorphism (shared low-frequency require)"
	fi
	if [ "${DOCTOR_DRYER_MIRROR:-}" = off ]; then
		[ -s "$T/tmirror" ] && echo "  ▽ mirrored copies: $(wc -l < "$T/tmirror") pairs (dryer-mirror off, collapsed)"
	else
		show_group "$T/tmirror" "▽ mirrored copies (same path below top-level dir)"
	fi
}

echo "── Dryer: repeated blocks (jscpd >=64 tokens) ──"
if command -v jscpd >/dev/null; then
	T=$(mktemp -d) && TAB=$(printf '\t')
	printf '%s\n' "$FILES" > "$T/members"
	jscpd_scan "$T" lua
	if [ -s "$T/pairs" ]; then
		dryer_classify
		dryer_report
	else
		echo "  (none)"
	fi
	rm -rf "$T"
else
	echo "  missing jscpd: npm i -g jscpd"
fi

exit 0
