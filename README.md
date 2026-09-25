# xiaofei — Sileo 越狱源

一个托管在 GitHub Pages 上的 **Sileo / Cydia** 越狱源。

## 源地址

| 项目 | 值 |
| --- | --- |
| 仓库 | `xiaofei/repo` |
| 默认源 URL | `https://xiaofei.github.io/repo/` |
| 一键添加（iOS） | `sileo://source/https://xiaofei.github.io/repo/` |

> 如果你的 GitHub 用户名不是 `xiaofei`，请把 `README.md` 与下面脚本里所有出现的 `xiaofei` 替换成你自己的用户名。

---

## 目录结构

```
xiaofei-repo/
├── debs/                 # 把 .deb 包放进这里
├── Release               # 源元数据（Sileo 识别这个文件）
├── Packages              # 包索引（由 dpkg-scanpackages 生成）
├── Packages.gz           # 压缩索引
├── Packages.xz           # 压缩索引
├── README.md
└── .gitignore
```

## 本地 / 服务器部署步骤

### 1. 创建 GitHub 仓库

在 GitHub 上新建仓库 `xiaofei/repo`（公开），然后：

```bash
cd xiaofei-repo
git init
git add .
git commit -m "init: xiaofei sileo source"
git branch -M main
git remote add origin git@github.com:xiaofei/repo.git
git push -u origin main
```

### 2. 启用 GitHub Pages

进入仓库 → **Settings → Pages**：

- **Source**：选 `Deploy from a branch`
- **Branch**：选 `main` / `/ (root)`
- 等 1 分钟左右，访问 `https://xiaofei.github.io/repo/Release` 能看到内容即可。

### 3. 在 Sileo 添加源

打开 Sileo → **Sources → +** → 输入：

```
https://xiaofei.github.io/repo/
```

或者用 iPhone Safari 直接点击：

```
sileo://source/https://xiaofei.github.io/repo/
```

---

## 怎么往源里加 .deb 包

### 方式 A：直接把 deb 放进 `debs/`

```bash
# 把你的 deb 拷过来
cp /path/to/your-pkg_1.0.0_iphoneos-arm.deb debs/

# 重新生成索引（macOS / Linux 都需要先安装 dpkg-dev）
dpkg-scanpackages -m debs /dev/null > Packages

# 生成压缩版本
gzip -9 -c Packages > Packages.gz
xz -c Packages > Packages.xz

# 更新 Release 里的校验和
./update-release.sh   # 仓库里没附此脚本，见下方「手填」说明
```

### 方式 B：手填 `Release` 的 SHA256

如果暂时没装 `dpkg-dev`，可以这样算哈希：

```bash
shasum -a 256 Packages | awk '{print $1}'   # 填到 Release 的 SHA256
shasum -a 1   Packages | awk '{print $1}'   # 填到 Release 的 SHA1
md5sum         Packages | awk '{print $1}'   # 填到 Release 的 MD5Sum
```

把得到的值粘贴进 `Release` 对应行：

```
MD5Sum:
 d41d8cd98f00b204e9800998ecf8427e   100 Packages
 SHA1:
 da39a3ee5e6b4b0d3255bfef95601890afd80709   100 Packages
 SHA256:
 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855   100 Packages
```

最后 `git add . && git commit && git push`，Sileo 刷新即可看到。

---

## 推荐的下一步（之后想自动化时再补）

- **GitHub Actions**：push 到 `main` 自动跑 `dpkg-scanpackages` 并发布到 `gh-pages`
- **本地打包脚本**：一键把 `debs/` 打成完整源
- **一键添加源按钮**：放在 `README` 顶部或博客里

---

## License

MIT