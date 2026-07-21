# 部署（Cloudflare Workers 静态资源）

`landing/` 是纯静态站点，通过 **Cloudflare Workers 的静态资源（Assets）** 功能部署——
Cloudflare 目前推荐用这个替代 Pages（`wrangler pages deploy` 已过时，用
`wrangler deploy`）。已上线在 **https://bartrans.met4.org**，作为 Custom Domain
挂在这个 Worker 上，跟 `met4.org` / `www.met4.org` 现有的 Vercel 网站完全独立、
互不影响。

配置文件是 `wrangler.jsonc`：

```jsonc
{
  "name": "bartrans",
  "compatibility_date": "2025-06-05",
  "assets": { "directory": "./dist" },
  "routes": [
    { "pattern": "bartrans.met4.org", "custom_domain": true }
  ]
}
```

`dist/` 里放的是实际要上线的文件（`index.html` + `icon.png` +
`bartrans-macOS.dmg` + `_headers`），跟 `landing/` 根目录下的同名文件是重复
的——根目录那份是编辑时用的工作副本，改完记得同步一份到 `dist/` 再部署。

## 更新并重新部署

```bash
# 1. 改完 landing/index.html 之后，同步到 dist/
cd /Users/czl/code/transpop/bartrans/landing
cp index.html icon.png _headers dist/

# 2. 如果 app 有更新，重新构建 dmg 并同步
cd /Users/czl/code/transpop/bartrans
./build_dmg.sh
cp .build/release/bartrans-macOS.dmg landing/bartrans-macOS.dmg
cp .build/release/bartrans-macOS.dmg landing/dist/bartrans-macOS.dmg

# 3. 部署
cd /Users/czl/code/transpop/bartrans/landing
npx wrangler@4 deploy
```

首次部署前需要 `npx wrangler@4 login`（走浏览器 OAuth），登录状态存在
`~/Library/Preferences/.wrangler/config/default.toml`，正常情况下只需要登录一次。

## 之前踩过的坑

- **`met4.org/bartrans` 路径不行**：`met4.org` 和 `www.met4.org` 的 DNS 记录是
  "仅 DNS"（灰云），没有走 Cloudflare 代理，Workers Route 只对代理流量生效，
  所以路径级的 Route 截不到任何请求。改用 `bartrans.met4.org` 作为独立子域名
  + Custom Domain（Cloudflare 自动建 DNS 记录和证书），不用碰现有的 Vercel 配置。
- **`wrangler` 本地配置文件权限问题**：`~/Library/Preferences/.wrangler/config/
  default.toml` 之前被 root 占用过（大概率是某次 `sudo` 运行 wrangler留下的），
  导致登录写不进去。修复：`sudo chown $(whoami) ~/Library/Preferences/.wrangler/
  config/default.toml`。
