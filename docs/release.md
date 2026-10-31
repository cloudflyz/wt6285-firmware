# 发布流程

## 触发

- 手动：Actions → build → Run workflow（构建 5.10 与 6.18 两个产物）
- 打标签：`git tag v1.0.0 && git push origin v1.0.0` → 除 artifact 外，自动创建 GitHub Release 并附上镜像、SHA256、buildinfo

## 产物命名

```
wt6285-5.10-<lean-sha7>-<原文件名>.bin
wt6285-6.18-<lean-sha7>-<原文件名>.bin
SHA256SUMS.txt
buildinfo.txt   # lean_sha / kernel / built_at / runner
```

## 校验

```sh
sha256sum -c SHA256SUMS.txt
```

## 版本约定

- 每次构建记录 `upstream.lock` 里的 lean SHA；升级基线就是改这个文件
- 发布标签建议 `v<日期>-<序号>`，例如 `v20261101-1`
