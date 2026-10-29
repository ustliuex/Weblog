---
title: 你好，世界
description: 博客的第一篇文章，用来验证发布流程是否正常工作。
pubDate: 2026-10-25
tags:
  - 随笔
  - 开场
---

这是本博客的第一篇文章。

**Astro + Cloudflare Pages** 的发布流程验证：写 Markdown → `git push` → 自动构建 → 读者访问。

## 代码示例

```typescript
function hello(name: string): string {
  return `Hello, ${name}!`;
}

console.log(hello('World'));
```
