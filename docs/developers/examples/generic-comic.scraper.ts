import { BaseScraper } from './base.scraper';
import type { ScrapedMetadata, ScraperMediaType } from './types';

const SCRAPER_NAME = 'Generic Comic Source';
const ID_PREFIX = 'generic-comic:';

// Synthetic example: replace the origin, routes and selectors with inspected
// source evidence. These selectors do not describe a real supported website.
const ORIGIN = 'https://source.example';
const SELECTORS = {
    result: '.work-result[data-work-id]',
    resultTitle: '.title',
    next: '.pagination a[rel="next"]',
    title: '.work-title',
    summary: '.work-summary',
    chapter: '.chapter[data-chapter-id]',
    image: '.reader img[data-page-id]'
};

export class GenericComicSource extends BaseScraper {
    public supportedTypes: ScraperMediaType[] = ['comic'];
    public baseUrl = ORIGIN;
    public importInputs = [{ kind: 'id' as const, example: 'generic-comic:work-123' }];

    constructor() { super(SCRAPER_NAME); }

    private async fetchPage(url: string) {
        const $ = await this.fetchHtml(url);
        return {$, url};
    }

    private required(value: string | undefined, field: string): string {
        const text = String(value || '').trim();
        if (!text) throw new Error(`Source is missing ${field}; inspect the current page structure`);
        return text;
    }

    private metadata(id: string, title: string, summary = ''): ScrapedMetadata {
        return { uniqueId: ID_PREFIX + this.required(id, 'work ID'), title: this.required(title, 'title'),
            summary, type: 'comic', source: SCRAPER_NAME, supportsVideo: false,
            posters: [], fanarts: [], thumbs: [] };
    }

    private rawId(id: string): string {
        if (!id.startsWith(ID_PREFIX)) throw new Error(`Expected a stable ${ID_PREFIX} ID`);
        return this.required(id.slice(ID_PREFIX.length), 'work ID');
    }

    async search(query: string, options: Record<string, any> = {}) {
        const page = Math.max(1, Math.floor(Number(options.page) || 1));
        const requestedSize = Math.max(1, Math.min(50, Math.floor(Number(options.pageSize) || 20)));
        const url = `${ORIGIN}/search?q=${encodeURIComponent(query)}&page=${page}&limit=${requestedSize}`;
        const result = await this.fetchPage(url);
        const $ = result.$;
        const items = $(SELECTORS.result).map((_, element) => this.metadata(
            $(element).attr('data-work-id') || '', $(element).find(SELECTORS.resultTitle).text()
        )).get();
        // Adapt both the upstream pagination parameter and the returned pageSize
        // to the real provider. Do not truncate an upstream page and skip items.
        return { items, page, pageSize: requestedSize, hasMore: $(SELECTORS.next).length > 0 };
    }

    async scrape(id: string): Promise<ScrapedMetadata | null> {
        const rawId = this.rawId(id);
        const url = `${ORIGIN}/comic/${encodeURIComponent(rawId)}`;
        try {
            const result = await this.fetchPage(url);
            return this.metadata(rawId, result.$(SELECTORS.title).text(), result.$(SELECTORS.summary).text().trim());
        } catch (error: any) {
            if (error?.response?.status === 404) return null;
            throw error;
        }
    }

    async getComicChapters(id: string) {
        const url = `${ORIGIN}/comic/${encodeURIComponent(this.rawId(id))}`;
        const result = await this.fetchPage(url);
        const $ = result.$;
        const chapters = $(SELECTORS.chapter).map((_, element) => ({
            id: this.required($(element).attr('data-chapter-id'), 'chapter ID'),
            title: this.required($(element).text(), 'chapter title'), kind: 'chapter' as const
        })).get();
        if (!chapters.length) throw new Error('Source returned no chapters; check readiness, access and pagination');
        // Collect the complete chapter catalog when the real source paginates it.
        return chapters;
    }

    async getComicPages(id: string, chapterId: string) {
        const url = `${ORIGIN}/read/${encodeURIComponent(this.rawId(id))}/${encodeURIComponent(this.required(chapterId, 'chapter ID'))}`;
        const result = await this.fetchPage(url);
        const $ = result.$;
        const pages = $(SELECTORS.image).map((index, element) => ({
            id: this.required($(element).attr('data-page-id'), 'stable page ID'),
            url: new URL(this.required($(element).attr('data-src') || $(element).attr('src'), 'image URL'), result.url).href,
            name: `${String(index + 1).padStart(4, '0')}.jpg`,
            headers: { Referer: result.url }
        })).get();
        if (!pages.length) throw new Error('Source returned no pages; check readiness and lazy loading');
        // Preserve provider reading order. Do not sort or deduplicate by signed URL.
        return pages;
    }
}
