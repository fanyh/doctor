# doctor 公共库:被各适配器 source,不是适配器(入口循环跳过 common.sh)
# jscpd 克隆管道:扫目录(对显式文件清单会损坏路径,压缩成残缺名);
# 串行 --workers 1(并发 worker 竞态改写克隆的文件名,同一对显示成两个同名文件);
# 排除做在结果层:配对任一侧不在成员清单、或命中 DOCTOR_EXCLUDE / DOCTOR_DRYER_EX(dryer: 行)即丢;
# 过滤打在剥出的路径上,不能打显示行(行尾是坐标,正则的 $ 会失配);
# 输出按 tokens 降序——jscpd 并发顺序不稳定,排序保证可复现。
# 产出:$1/pairs 每行 "序号\t路径A\t路径B\ttokens";$1/b.序号 为该对的显示块。
# 调用方先写好 $1/members(参与检测的文件,一行一个)
jscpd_scan() { # $1=临时目录 $2=jscpd format
	jscpd --min-tokens 64 --format "$2" --workers 1 --reporters console . 2>/dev/null \
		| sed 's/\x1b\[[0-9;]*m//g' \
		| awk -v tdir="$1" '
		BEGIN { while ((getline ml < (tdir "/members")) > 0) mem[ml]=1
		       n=split(ENVIRON["DOCTOR_EXCLUDE"], L, "|"); for (i=1;i<=n;i++) exr[i]=L[i]
		       m=split(ENVIRON["DOCTOR_DRYER_EX"], D, "\n"); for (i=1;i<=m;i++) { sub(/^dryer:[[:space:]]*/,"",D[i]); dpr[i]=D[i] } }
		/^Clone found/ { hdr=$0; state=1; next }
		state==1 { pa=$0; state=2; next }
		state==2 { pb=$0; state=0
		           fa=pa; fb=pb; sub(/^ +- /,"",fa); sub(/^ +/,"",fb); sub(/ \[.*/, "", fa); sub(/ \[.*/, "", fb)
		           skip=0
		           if (!(fa in mem) || !(fb in mem)) skip=1
		           for (i=1;i<=n;i++) if (fa ~ exr[i] || fb ~ exr[i]) { skip=1; break }
		           for (i=1;i<=m;i++) if (fa ~ dpr[i] || fb ~ dpr[i]) { skip=1; break }
		           if (!skip) { k++; blk[k]=hdr "\n" pa "\n" pb; meta[k]=fa "\t" fb "\t" tok(blk[k]) } }
		function tok(s) { if (match(s, /[0-9]+ tokens/)) { t=substr(s, RSTART, RLENGTH); sub(/ tokens/, "", t); return t+0 } return 0 }
		END { for (i=2;i<=k;i++) { v=blk[i]; mv=meta[i]; vt=tok(v)
		      for (j=i-1;j>=1 && tok(blk[j])<vt;j--) { blk[j+1]=blk[j]; meta[j+1]=meta[j] }
		      blk[j+1]=v; meta[j+1]=mv }
		      for (i=1;i<=k;i++) { print blk[i] > (tdir "/b." i); print i "\t" meta[i] > (tdir "/pairs") } }'
}
