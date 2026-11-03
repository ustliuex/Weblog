---
title: 从零搭建 Astro 博客：我的技术选型与踩坑记录
description: 记录搭建本博客过程中的技术决策：Astro vs Next.js、Cloudflare Pages vs GitHub Pages、PowerShell 代理配置，以及那些花了半小时才找到答案的小坑。
pubDate: 2026-11-03
updatedDate: 2026-11-03
tags:
  - 工程实践
  - Astro
  - 博客
draft: false
---

> "写博客不是为了写给别人看，而是为了把自己脑中模糊的想法逼成清晰的文字。"
> —— 某个我记不住名字的人

## 为什么又搭了一个博客

说起来这已经是我第三次搭博客了。前两次分别用了 Hexo 和 Hugo，都没坚持下来——不是框架不好，而是**部署和维护的摩擦成本太高**。这次的目标很简单：

1. **零运行时**：静态生成，部署到免费平台不心疼
2. **写作体验优先**：Markdown + frontmatter，不要 CMS
3. **图片能正常显示**：这是硬需求，之前 Hugo 的图片处理让我头疼了好久

最终方案：**Astro + Cloudflare Pages + Git 仓库内图片**。

## 技术选型对比

| 维度 | Astro | Next.js | Hexo | Hugo |
|---|---|---|---|---|
| 渲染模式 | SSG / SSR / ISR | SSG / SSR / ISR | 纯 SSG | 纯 SSG |
| 运行时 JS | 零（默认） | 较多 | 零 | 零 |
| 内容组织 | Content Collections | MDX / 外部 CMS | Front-matter | Front-matter |
| 学习曲线 | 中 | 高（需 React） | 低 | 低 |
| 图片优化 | `astro:assets` 内置 | `next/image` | 需插件 | 需 Shortcode |

选 Astro 的核心理由：**Content Collections 的 schema 校验**——frontmatter 字段写错会直接报错，而不是默默渲染出一篇缺标题的文章。对一个不想花精力维护的个人博客来说，这种"构建失败比静默出错好"的哲学太重要了。

## 架构总览

```
                    ┌─────────────┐
                    │   GitHub    │
  ustliuex/weblog   │  (git repo) │
                    └──────┬──────┘
                           │ push
                           ▼
                    ┌─────────────┐
                    │ Cloudflare  │
                    │   Pages     │
                    │  (build +   │
                    │   CDN 分发) │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        xxx.pages.dev  自定义域名     国内加速
```

**初期**用 `ustliuex.pages.dev`，将来换自有域名只改三处：

1. `astro.config.mjs` 的 `site` 字段
2. Cloudflare Pages → Custom Domains → 绑定新域名
3. DNS 的 CNAME 记录

**全程不动文章**。这是我最在意的设计原则——文章内容和部署基础设施解耦。

## 踩坑记录

### 坑 1：PowerShell 下 `2>&1` 不是 bash 语法

把 bash 习惯带到 PowerShell 5 里，写了 `npm run build 2>&1 | Select-Object -Last 5`，结果报：

```
调用运算符 "&" 后跟的 "1" 不是有效命令
```

PowerShell 5 的流重定向是独立的语法体系，没有继承 bash 的 `2>&1`。**PowerShell 7+ 才引入了 Unix 风格的流合并**。如果你还在用 PowerShell 5，要么升级，要么绕路用 `2>&1 | Out-String`。

### 坑 2：git init 的位置

`git init` 建在了 `web-dev/` 父目录，而不是 `blog/` 子目录。结果：

- 把 `.trae-html-share-packages/`、`blog-prd/` 等不该公开的东西卷进了公开仓库
- 空仓库零提交，`git push -u origin main` 报 `src refspec main does not match any`

**正确做法**：`cd blog && git init`。

### 坑 3：GitHub 直连不稳定

国内直连 GitHub 经常 `Connection timed out`。你的代理 PAC 脚本声明了 `127.0.0.1:51081`，Git 全局配置后问题解决：

```powershell
git config --global http.proxy  http://127.0.0.1:51081
git config --global https.proxy http://127.0.0.1:51081
```

> 注：公司内网如果不需要代理，记得 `git config --global --unset http.proxy https.proxy`。

## 写作工作流

目前的流程比较顺手：

```
VS Code 打开 blog/
  → 新建 src/content/blog/YYYY-MM-DD-文章名.md
  → 输入 afm + Tab 展开 frontmatter 模板
  → 填 title / description / tags
  → Ctrl+Shift+V 侧边预览
  → Ctrl+V 粘贴图片 → 自动存到 public/images/
  → npm run dev 完整预览
  → git add + commit + push
  → Cloudflare Pages 自动构建并部署
```

## 下一步计划

- [ ] 接入 giscus 评论（等文章有几篇了再说）
- [ ] 试试 Pagefind 搜索体验
- [ ] 写一篇真正的研究笔记，验证长文渲染
- [ ] 等域名备案完成后绑定自有域名

---

如果这篇文章能被正常渲染出来，说明整个发布链路跑通了。🎉
