#!/bin/sh
# doctor 适配器:Go —— gocyclo×覆盖 → CRAP / dupl / deadcode
# 范围:DOCTOR_SCOPE=auto(有未提交改动→diff,否则整仓)/diff/all
# 注意:awk 双文件 join 一律用 FILENAME==ARGV[1](NR==FNR 在首文件为空时是错的)
[ -f go.mod ] || exit 3
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
EX='examples|/test/'
[ -n "${DOCTOR_EXCLUDE:-}" ] && EX="$EX|$DOCTOR_EXCLUDE"
T="$(mktemp -d)" && trap 'rm -rf "$T"' EXIT

command -v gocyclo  >/dev/null || { echo "== Go(go.mod)=="; echo "  missing gocyclo:  go install github.com/fzipp/gocyclo/cmd/gocyclo@latest"; exit 0; }
command -v dupl     >/dev/null || { echo "  missing dupl:     go install github.com/mibk/dupl@latest"; exit 0; }
command -v deadcode >/dev/null || { echo "  missing deadcode: go install golang.org/x/tools/cmd/deadcode@latest"; exit 0; }

# ── 范围判定 ──(隐藏目录/.opencode 草稿不算改动)
GITFiles() { { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | grep '\.go$' | grep -Ev "$EX" | grep -vE '(^|/)\.' | sort -u; }
SCOPE=${DOCTOR_SCOPE:-auto}
CHANGED=$(git rev-parse --is-inside-work-tree >/dev/null 2>&1 && GITFiles || true)
[ "$SCOPE" = diff ] && [ -z "$CHANGED" ] && SCOPE=all
if [ "$SCOPE" = auto ]; then
	[ -n "$CHANGED" ] && SCOPE=diff || SCOPE=all
fi

if [ "$SCOPE" = diff ]; then
	echo "== Go (go.mod, scope: diff, $(printf '%s\n' "$CHANGED" | wc -l | tr -d ' ') files) =="
else
	echo "== Go (go.mod, scope: all) =="
fi

PKGS=$(go list ./... 2>/dev/null | grep -Ev "$EX" || true)
[ -n "$PKGS" ] || { echo "  (no packages)"; exit 0; }
DIRS=$(for p in $PKGS; do go list -f '{{.Dir}}' "$p"; done | sort -u)

# ── 覆盖(全量跑,缓存很快)──
: > "$T/cov"
for p in $PKGS; do
	go test -coverprofile="$T/c" "$p" >/dev/null 2>&1 || true
	[ -f "$T/c" ] && tail -n +2 "$T/c" >> "$T/cov"
done
sed -i '1i mode: set' "$T/cov"
# covf 每行: 函数名(裸) 覆盖率(数字) 仓库相对路径(join 键升级为完整路径,防同名文件串门)
MODULE=$(sed -n 's/^module //p' go.mod | head -1 | tr -d ' \r')
go tool cover -func="$T/cov" | awk -F'\t+' -v m="$MODULE" '$2!="" && $2!="(statements)" {gsub(/%/,"",$3); sub("^"m"/","",$1); print $2, $3, $1}' \
	| sed 's/:[0-9]*:$//' > "$T/covf"

if [ "$SCOPE" = diff ]; then
	FILES=$(printf '%s\n' "$CHANGED" | grep -v '_test.go$' | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
else
	# 清单是仓库相对路径:与覆盖表的 join 键对齐(绝对路径会让全仓模式的覆盖列全成 --)
	FILES=$(grep '\.go$' "${DOCTOR_FILELIST:-/dev/null}" 2>/dev/null | grep -v '_test.go$' | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
	[ -n "$FILES" ] || FILES=$(find $DIRS -name '*.go' ! -name '*_test.go')
fi

# cb 供 Crapper/Dryer/Mutator 共用；tests-only 时 Crapper 段跳过，不能只在段内生成
if [ "$SCOPE" = diff ]; then
	printf '%s\n' "$CHANGED" > "$T/cb"
fi

echo "── Crapper: CRAP >= 10 ──"
if [ -z "$FILES" ]; then
	echo "  (none)"
else
# funcs 每行: 函数名 分支 join路径(无行号,对 cover/deadcode) 显示路径(带声明行)
gocyclo -over 0 $FILES | awk '{n=$3; sub(/.*\./,"",n); d=$NF; sub(/:[0-9]+$/,"",d); p=d; sub(/:[0-9]+$/,"",p); print n, $1, p, d}' \
	| sort -u > "$T/funcs"

# 函数级排除:.doctorignore 的 路径正则::函数名正则
if [ -n "${DOCTOR_FUNCS_EX:-}" ]; then
	awk '
	BEGIN { fx=ENVIRON["DOCTOR_FUNCS_EX"]; m=split(fx, L, "\n"); for (i=1;i<=m;i++) { split(L[i], kv, "::"); fp[i]=kv[1]; fn[i]=kv[2] } }
	{ skip=0; for (i=1;i<=m;i++) if ($3 ~ fp[i] && $1 ~ fn[i]) { skip=1; break }; if (!skip) print }' \
		"$T/funcs" > "$T/x" && mv "$T/x" "$T/funcs"
fi

# ── 范围过滤:diff 模式下只留改动文件内的条目(按完整相对路径) ──
if [ "$SCOPE" = diff ]; then
	awk 'FILENAME==ARGV[1] { c[$1]=1; next } ($3 in c)' "$T/cb" "$T/covf" > "$T/x" && mv "$T/x" "$T/covf"
	awk 'FILENAME==ARGV[1] { c[$1]=1; next } ($3 in c)' "$T/cb" "$T/funcs" > "$T/x" && mv "$T/x" "$T/funcs"
fi

out=$(awk 'FILENAME==ARGV[1] { cov[$1"_"$3]=$2; next }
{ c=($1"_"$3 in cov)?cov[$1"_"$3]:-1; comp=$2;
  crap=(c<0)?comp:comp*comp*((100-c)/100)^3+comp;
  if (crap>=10) printf "  %-22s %6.1f %4d %-6s (%s)\n", $1, crap, comp, (c<0?"--":c"%"), $4 }' \
	"$T/covf" "$T/funcs" | sort -k2 -rn)
	[ -n "$out" ] && { printf "  %-22s %6s %4s %-6s %s\n" Function CRAP Comp Cov Path; echo "$out"; } || echo "  (none)"
fi

echo "── Dryer: repeated blocks (>=64 tokens) ──"
if [ "$SCOPE" = diff ]; then
	out=$(dupl -threshold 64 $DIRS 2>/dev/null | grep '\.go:' | grep -v '_test.go' | grep -F -f "$T/cb")
else
	out=$(dupl -threshold 64 $DIRS 2>/dev/null | grep '\.go:' | grep -v '_test.go')
fi
[ -n "$out" ] && echo "$out" || echo "  (none)"

# ── Mutator:调用图是全局的,全量分析后按范围过滤 ──
# 只报完全不可达:deadcode --test 把测试/example 全算进调用图,谁都不引用的才是真死
# dead 每行: 函数名 仓库相对路径
deadcode --test ./... 2>/dev/null | grep -Ev "$EX" | awk -F'func: ' '{n=$2; sub(/.*\./,"",n); split($1,p,"/"); f=p[length(p)]; sub(/:.*/,"",f); ip=$1; sub(/:[0-9]+:[0-9]+:.*/,"",ip); if (n ~ /^[a-z]/) print n, ip}' | sort -u > "$T/dead"
if [ "$SCOPE" = diff ]; then
	awk 'FILENAME==ARGV[1] { c[$1]=1; next } ($2 in c)' "$T/cb" "$T/dead" > "$T/x" && mv "$T/x" "$T/dead"
fi

# dense:输出聚合——条目 ≤10 全列,超过按文件一行(一族函数不是散点,密度跟着问题粒度走)
# 输入每行: 函数名 路径
dense() {
awk '{ n=$1; p=$2; c[p]++; if (!(p SUBSEP n in seen)) { seen[p,n]=1; if (c[p]<=5) s[p]=s[p]" "n } ; l[++k]=$0 }
END {
	if (k<=10) { for (i=1;i<=k;i++) { split(l[i],a," "); printf "  %s (%s)\n", a[1], a[2] } }
	else for (p in c) printf "  %s ×%d:%s%s\n", p, c[p], s[p], (c[p]>5?" ...":"")
}' | sort
}

echo "── Mutator: dead code ──"
out=$(dense < "$T/dead")
[ -n "$out" ] && echo "$out" || echo "  (none)"
exit 0
