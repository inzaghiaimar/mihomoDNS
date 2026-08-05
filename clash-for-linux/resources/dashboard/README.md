# Dashboard 资产说明

- 上游项目：[Zephyruso/zashboard](https://github.com/Zephyruso/zashboard)
- 上游版本：`3.15.0`
- 上游提交：`0d2a7b5c0ac6f67085f32ad3d08d6b4a63e24d42`
- 本地补丁：`zashboard-issue-290.patch`

本地补丁修正了“网络信息”容易被误认为后端代理出口的问题。该查询由浏览器直接访问 IP 信息服务，因此显示的是浏览器出口 IP；补丁会明确标注这一点，并提示它可能与后端代理出口不同。

重新构建：

```bash
git clone https://github.com/Zephyruso/zashboard.git
cd zashboard
git checkout 0d2a7b5c0ac6f67085f32ad3d08d6b4a63e24d42
git apply --unidiff-zero ../clash-for-linux/resources/dashboard/zashboard-issue-290.patch
pnpm install --frozen-lockfile
pnpm run type-check
pnpm run build
cp LICENSE dist/LICENSE
zip -r dist.zip dist
```

生成的 `dist.zip` 用于替换本目录中的同名文件。Zashboard 使用 MIT 许可证，许可证正文已包含在压缩包的 `dist/LICENSE` 中。
