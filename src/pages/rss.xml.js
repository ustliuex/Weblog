import rss from '@astrojs/rss';

export async function GET(context) {
	const mods = import.meta.glob('../content/blog/**/*.{md,mdx}', { eager: true });
	const posts = Object.entries(mods)
		.map(([path, mod]) => ({
			id: path.replace('../content/blog/', '').replace(/\.(md|mdx)$/, ''),
			data: mod.frontmatter,
		}))
		.filter((p) => !p.data.draft)
		.sort((a, b) => new Date(b.data.pubDate).valueOf() - new Date(a.data.pubDate).valueOf());

	return rss({
		title: 'UST Liuex\'s Weblog',
		description: '学习笔记、研究随笔与创作记录',
		site: context.site,
		items: posts.map((post) => ({
			title: post.data.title,
			description: post.data.description,
			pubDate: new Date(post.data.pubDate),
			link: `/posts/${post.id}/`,
		})),
	});
}
