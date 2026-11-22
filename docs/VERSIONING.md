# 版本与发布路径

## 版本格式

基版本只有一个，写在仓库根目录的 `VERSION`：

```text
X.YY.ZZ
```

- `X`：重大变更，从 `0` 开始；
- `YY`：小幅度迭代，固定两位（`00`、`01` …… `10`）；
- `ZZ`：hotfix 迭代位，两位；每成功的 dev 构建把它推进一格，满 99 自动进位到
  `YY`（`YY` 满 99 进位到 `X`）。

`VERSION` 只在要换迭代线时手动改。日常提交不改它，dev 构建时自动计算：

```text
一次成功的 dev 构建 = hotfix 迭代一次：ZZ+1，并把新版本写回 beta:VERSION.latest
```

计数的载体是 `VERSION.latest`，不是 commit：构建成功、写回记录的那一刻，hotfix
迭代一格；失败或被取消的构建不写回、不迭代。数字表达的是 hotfix 版本前进了几步，
不是构建跑了几次，更不是提交了几次——这是从 commit 计数改来的原因，前期密集提交
不会把版本号撑大。以 `VERSION = 0.00.00` 为例：

| 迭代 | dev 版本 |
|---|---|
| `VERSION` 变更后的第 1 次成功构建 | `0.00.00.Dev` |
| 第 2 次成功构建 | `0.00.01.Dev` |
| 第 3 次成功构建 | `0.00.02.Dev` |
| `0.00.99` 之后的下一次迭代 | `0.01.00.Dev`（自动进位） |

连续快速 push 会取消上一次未完成的构建（并发组 `cancel-in-progress`），
所以版本号的增长只会慢于提交数，不会更快。进位发生在版本号上，`VERSION` 不被
CI 改写：进位后记录的 `base:` 行仍与它一致，迭代在进位后的号上继续。

**只有 dev 做这个加法。** beta 与 stable 原样继承 dev 的版本号，不再 +1：
dev 的 `0.00.02.Dev` 晋升后就是 `0.00.02.Beta`，再晋升就是 `0.00.02`。
补零让所有版本等长，排序和匹配都不需要额外规则；输入 `0.1.0` 这类简写时会自动补成 `0.01.00`。

通道是版本的最后一段，不使用 run 号：

| 通道 | 版本 | 来源 | 发布位置 |
|---|---|---|---|
| dev | `X.YY.ZZ.Dev` | 仅 beta 分支 push 自动构建（ZZ 为 hotfix 迭代位） | Actions artifact（**不进 Release**） |
| beta | `X.YY.ZZ.Beta` | 手动从最新 dev 产物晋升，版本号不变 | GitHub prerelease |
| stable | `X.YY.ZZ` | 手动从最新 beta 产物晋升（也可从 dev 直通），版本号不变 | GitHub Release |

`run` 只出现在 dev artifact 的名字里用于区分多次构建，不进入版本号，也不进入最终产物。

## 发布产物

| 通道 | 产物 |
|---|---|
| dev | `XnX-Player-Portable-X.YY.ZZ.Dev-<run>`（Actions artifact，下载即便携 zip） |
| beta | `XnX-Player-Portable-X.YY.ZZ.Beta.zip` + `XnX-Player-Setup-X.YY.ZZ.Beta.exe` |
| stable | `XnX-Player-Portable-X.YY.ZZ.zip` + `XnX-Player-Setup-X.YY.ZZ.exe` |

- **便携版**解压即用，包内 `data-dir.txt` 写的是 `userdata`，数据落在程序目录
  （不能叫 `data`——那是 Flutter 的运行时资源目录）。
- **安装包**由 Inno Setup 编译（`installer/xnx.iss`）：向导先显示 `LICENSE` 与
  `INSTALL.txt`，可更改安装目录；数据目录可在「默认（`%APPDATA%\XnX Player`）」
  「程序目录下的 `userdata`」「自定义目录」之间选择，安装结束时写入 `data-dir.txt`。
- 应用内更新只使用便携版 zip；stable/beta 从 Release 资产取，dev 从 Actions
  产物取（需要 `XNX_GITHUB_TOKEN`）。

## 快速改基版本

dev 构建只由 push 触发，**基版本唯一来源是仓库根目录的 `VERSION` 文件**。

早期版本支持用仓库变量 `XNX_VERSION` 覆盖，但它对仓库不可见、晋升后需要手动同步，
一旦忘记就会让后续构建一直沿用旧版本号。该变量已移除：CI 只读 `VERSION`，避免
"构建拿到了版本号却没落到仓库、下次又算回旧值"的问题。

日常迭代**不需要** bump：每次成功的 dev 构建就是一次 hotfix 迭代，ZZ 推进一格。每次 dev 构建还会把
实际产出的版本号与构建时的基版本写回 beta 分支的 `VERSION.latest`（两行，提交带
`[skip ci]`，不会触发新构建）：

```text
0.00.16.Dev
base: 0.00.00
```

这份记录同时是**下一次构建的计数来源**和 promote 晋升时的交叉核对材料：下次构建
读它的 `ZZ+1`，并用 `base:` 行判断 `VERSION` 变没变——变了就从新基数重新计数
（比较版本号本身做不到这一点，正常累积下版本号与基数本来就不同）。
`VERSION` 本身不会被 CI 改写——它是计数比对的基准，改写会让计数归零、版本回退。
记录里没有 `base:` 行的旧格式也能读：此时按 `X.YY` 判断是否换线，匹配则继续累积。

只有在要开新的迭代线时才手动改基版本：

```bash
dart run tool/version.dart bump minor   # 0.00.03 -> 0.01.00
dart run tool/version.dart bump major   # 0.01.07 -> 1.00.00
```

`bump patch` 仍然保留，用来重置 hotfix 基数（比如想跳过一段累计的 dev 号）；它和手改 `VERSION` 一样，下次成功构建会从新基数重新开始。

没有 Flutter/Dart SDK：

```powershell
powershell -ExecutionPolicy Bypass -File tool/bump-version.ps1 -Part minor
```

两者都会更新 `VERSION` 与 `pubspec.yaml` 的 `version:`（自动补足两位）。提交并 push 到 **beta 分支**后，下一次成功的 dev 构建就是新基版本本身（如 `0.02.00.Dev`），之后每次成功构建再加一。PowerShell 脚本加 `-Push` 可直接提交并推送。

### 仓库变量（已停用）

`XNX_VERSION` 仓库变量已停用；若 Settings → Variables 里还留着它，删掉即可，CI 不再读取。
基版本只认 `VERSION` 文件，最近一次 dev 版本记录在 beta 分支的 `VERSION.latest`。

### 从提交推导

```bash
dart run tool/version.dart auto --write
```

规则：`BREAKING CHANGE` / `feat!:` → major；`feat:` → minor；其余 → patch。有 tag 时从最近的 `v*` tag 起算，没有 tag 时以 `VERSION` 为起点。

## 发布路径

### 1. dev

只有 push 到 **beta 分支**才会自动构建，ZZ 按成功构建次数累加（读 `VERSION.latest` 取 +1），只上传 Actions artifact，不创建 Release。`dev-build` 没有手动入口——手动构建走下面的 promote，产物永远是 beta 或 stable，且不会再次加一。

### 2. dev → beta

在 Actions 手动触发 **promote**，选择 `target=beta`：

```bash
gh workflow run promote.yml -f target=beta
```

工作流取**最新的 dev 产物**（可用 `version` 指定基版本，`0.1.0` 这类简写会补成 `0.01.00`），把产物内的 `version.txt` 从 `X.YY.ZZ.Dev` 改为 `X.YY.ZZ.Beta`，打成便携版 zip，再用 Inno Setup 编译安装包，以 `vX.YY.ZZ.Beta` 发布为 prerelease（两个资产）。**不重新编译**，发布的就是 dev 验证过的那份文件。

### 3. beta → main

beta 验证通过后，手动触发 **merge-main**：

```bash
gh workflow run merge-main.yml
```

把 `beta` 合并进 `main`。这一步只搬代码，不构建、不发布。

### 4. beta → stable

手动触发 **promote**，选择 `target=stable`：

```bash
gh workflow run promote.yml -f target=stable
```

工作流优先取**最新的 beta Release 里的便携版资产**（可用 `version` 指定）；如果该基版本还没有 beta 发布，就回退到最新 dev 产物（`dev → stable` 直通）。把 `version.txt` 的通道段改成 `X.YY.ZZ`，打成便携版 zip 并编译安装包，以 `vX.YY.ZZ` 发布为正式 Release。版本号本身不变，同样**不重新编译**。

### 路径总结

```text
beta 分支 push ──> X.YY.ZZ.Dev（artifact，不进 Release）
                        │
                        ▼  promote target=beta（手动）
                  X.YY.ZZ.Beta（prerelease）
                        │
          ┌─────────────┴─────────────┐
          ▼                           ▼
 merge-main.yml              promote target=stable（手动）
  beta -> main                  X.YY.ZZ（Release）
```

两条路径都合法：`dev → beta → stable`（stable 取 beta 资产）和 `dev → stable`（没有 beta 发布时直接取 dev 产物）。无论在哪个通道，版本号都保持 dev 构建时算出的值，不会因为晋升再加一。

## 运行时版本

构建时 CI 会：

1. 把最终版本作为 `--dart-define=APP_VERSION=<version>` 编进程序；
2. 在 Release 目录写 `version.txt`。

晋升时只改写 `version.txt`。程序启动优先读可执行文件旁的 `version.txt`，因此 beta/stable 产物显示的版本就是晋升后的通道版本，而不是编译时的 dev 字符串。
