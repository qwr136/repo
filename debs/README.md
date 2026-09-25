# 把 .deb 包放在这里

把这个目录里的 `.deb` 文件视作本源的 deb 包。

提交后执行：

```bash
dpkg-scanpackages -m debs /dev/null > Packages
gzip -9 -c Packages > Packages.gz
xz -c Packages > Packages.xz
```

然后把 `Packages` / `Packages.gz` / `Packages.xz` 的 SHA256 写进 `Release`。