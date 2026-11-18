# doctor

工程级 CDM 审计工具:对整个仓库做 **Crapper**(复杂度×测试)· **Dryer**(重复)· **Mutator**(死代码)三类交叉分析,lint 式报告,不评分。

## 定位与边界

| 工具 | 视角 | 信号 |
|---|---|---|
| LSP / 编辑器 | 单文件,编辑时实时 | unused、类型、格式 |
| **doctor** | 全仓,按需运行 | 复杂度×覆盖(CRAP)、克隆配对、死代码 |
| AI / 人工 review | 语义与架构 | 业务正确性、改造方案与实施 |

doctor 只输出诊断——哪里、多少、多严重;不输出解决方案,方案与实施由开发者或 AI 代理完成(见"配合 AI 使用"),报告中的"拆/补测"提示是读表参考。语法与语义正确性归 LSP/编译器;终止性(死循环)静态不可判定,建议用运行时看门狗检测。

## 依赖

按语言,缺哪个就少哪段输出,不会崩:

| 语言 | Crapper | Dryer | Mutator |
|---|---|---|---|
| Go | gocyclo + go test -cover | dupl | deadcode |
| Lua | luacheck | jscpd | —(逐文件 unused 归 LSP) |
| Python | radon | jscpd | vulture |
| sh | 内置关键字计数(嵌入 awk 的控制流也计入) | jscpd(无扩展名文件不在其扫描面) | —(unused/quote 归 shellcheck) |

```sh
go install github.com/fzipp/gocyclo/cmd/gocyclo@latest
go install github.com/mibk/dupl@latest
go install golang.org/x/tools/cmd/deadcode@latest
luarocks install luacheck
npm i -g jscpd
pipx install radon vulture
```

要求 POSIX sh + GNU grep/sed/awk(grep 的 `\x27` 转义用到 GNU 扩展)。

**平台**:Linux / macOS / **WSL2**(Windows 的官方路径,`wsl --install` 即得完整工具链;仓库放 WSL 文件系统内,`/mnt/c` 跨盘 I/O 慢)。Git Bash 带 GNU 工具但未验证,CRLF 会让 awk 的 `$` 锚失配;原生 PowerShell/CMD 不支持。

## 安装

```sh
make install     # 软链 bin/doctor → ~/.local/bin/doctor
make uninstall
```

## 用法

```sh
doctor [--all|--diff] [目录]
```

- 范围:**自动**——仓库有未提交改动只查改动文件(diff),干净则整仓;`--all` 强制整仓,`--diff` 强制只查改动
- 语言:自动探测(有 go.mod → Go;有 *.lua → Lua;有 *.py → Python;有 *.sh 或 sh shebang 的文件 → sh),多语言并存时逐个跑
- 新语言 = 在 `lib/doctor/` 放一个 `<lang>.sh`(约定见下)

## 过滤:.gitignore ∪ .doctorignore

文件清单取 git 视角(tracked + 未忽略的 untracked)——`.gitignore` 自动生效;隐藏目录(`.git/`、编辑器草稿目录)一律不算;非 git 目录用 find 兜底。在此之上,工程根目录的 `.doctorignore`,每行一个 ERE 正则(子串匹配路径,不是通配符),`#` 注释(支持行内):

```
package/                        # 文件级:全维度排除(打包产物/第三方目录)
json\.lua::encode2              # 函数级:只压 Crapper 里的某个函数(第三方大函数)
dryer: test\.lua$               # Dryer 级:clone 配对任一侧命中即不报
dryer-poly off                  # 关闭"疑似多态"归组展开,收成一行计数
dryer-mirror off                # 关闭"同路径镜像"归组展开,收成一行计数
```

## 输出解读

- **Crapper**(CRAP ≥ 10):分支 >10 → 拆函数;分支 ≤10 → 补测试(Go 有覆盖数据时按 CRAP 公式,无覆盖数据的语言退化为分支数)
- **Dryer**(≥64 token 重复块):主列表 = 无亲缘的真重复;Lua 侧自动归组两类**有意相似**——疑似多态(两侧 require 同一低频模块,按基类聚合)与同路径镜像(去掉顶层目录后路径相同的跨树副本);归组不静默压,全量可见
- **Mutator**(谁都不引用):生产/测试/example 全算进调用图后仍不可达才报,反射/构建标签盲区自行核对

## 新增适配器约定

`lib/doctor/<lang>.sh`,由入口 `sh` 调用,工作目录已是工程根。公共 jscpd 管道在 `lib/doctor/common.sh`(`jscpd_scan`,各适配器 source;入口循环跳过它):

- 无该语言文件时 `exit 3`(非 0 且非 0 输出即"我没东西查")
- 环境变量:`DOCTOR_SCOPE`(auto/diff/all)、`DOCTOR_EXCLUDE`(文件级排除,`|` 连接的 ERE)、`DOCTOR_FUNCS_EX`(函数级,`路径::函数` 每行一条)、`DOCTOR_DRYER_EX`(dryer: 行)、`DOCTOR_DRYER_POLY`/`DOCTOR_DRYER_MIRROR`(off 即关)
- 段落格式:`== <语言> ==` 头 + `── <维度>:<一行说明>──` 三段,缺工具打印安装提示不崩

## 设计原则

- **只诊断不处方**:doctor 给数字和清单,不给改造方案;方案与实施归 AI(推荐 ub-mode)或人工 review
- **可复现**:jscpd 固定 `--workers 1`(并发会竞态改写克隆文件名)、输出按重复块大小降序——同一仓库每次跑结果逐字节一致
- **不静默压**:所有过滤(排除/函数/dryer:/归组开关)只影响显示归置,不悄悄吞条目;归组关闭也保留一行计数
- **启发式只分拣不决策**:多态/镜像识别是文本层启发式,覆盖不了的继承风格漏进主列表,由 `dryer:` 正则收尾

## 配合 AI 使用

doctor 的输出刻意做成 AI 可直接消费的 lint 式报告:固定分段、路径带行号、同仓库逐字节可复现——它就是给 agent 当"工程体检"用的听诊器。

- **让 AI 消费报告**:跑一次 doctor = 一次体检,Crapper/Dryer/Mutator 三张报告交给 agent,按"拆/补测、合并、删"开处方
- **让 AI 验证改动**:输出确定性意味着可以落盘对账——`doctor > a` → 改代码 → `doctor > b` → `diff a b`,前后差异精确可证
- **让 AI 扩语言**:适配器 = 一个 sh 文件 + 固定约定(见"新增适配器约定"),模型照现有三个模板写第四个

单独跑 doctor 只是一份报告,报告的收益兑现在编码回路里。配合 [ub-mode](https://github.com/unclebob/ub-mode) 使用收益最大:它点名的 crapper/dryer/mutator 工具位由 doctor 补上,质量门从口号变成逐函数清单;诊断由此进入 AI 编码过程——改前 `doctor > a` 立基线,编码时带着诊断上下文(不新增超标函数/克隆,顺手减存量),改后 `doctor > b; diff a b` 对账,diff 结论即 commit 的 "how you proved it"。

## 鸣谢

- [ub-mode](https://github.com/unclebob/ub-mode)(Robert C. Martin):Crapper / Dryer / Mutator 三维度审计及其门槛(函数 CRAP 降到 10 以下、消除重复、删除死代码)源自该 skill 的质量门,doctor 是它们的工程级、可复现实现。

## 作者

[fanyh](https://github.com/fanyh) · Apache-2.0

