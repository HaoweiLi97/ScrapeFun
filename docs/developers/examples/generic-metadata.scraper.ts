import { BaseScraper } from './base.scraper';
import type { ScrapedMetadata, ScraperMediaType } from './types';
import { networkAxios } from '../utils/network-proxy';

// Synthetic API contract. Replace the endpoint and field mapping after inspection.
const SCRAPER_NAME = 'Generic Metadata Source';
const API_URL = 'https://metadata.example/api';
const ID_PREFIX = 'generic-metadata:';

export class GenericMetadataSource extends BaseScraper {
    public supportedTypes: ScraperMediaType[] = ['movie'];
    public importInputs = [{kind: 'id' as const, example: 'generic-metadata:123'}];
    public baseUrl = API_URL;

    constructor() { super(SCRAPER_NAME); }

    private rawId(id: string): string {
        if (!id.startsWith(ID_PREFIX) || !id.slice(ID_PREFIX.length).trim()) {
            throw new Error(`Expected a stable ${ID_PREFIX} ID`);
        }
        return id.slice(ID_PREFIX.length);
    }

    private metadata(row: any): ScrapedMetadata {
        if (!row || row.id == null || !String(row.id).trim() || !String(row.title || '').trim()) {
            throw new Error('Source metadata is missing an ID or title');
        }
        return {
            uniqueId: ID_PREFIX + String(row.id), title: String(row.title).trim(),
            originalTitle: typeof row.originalTitle === 'string' ? row.originalTitle : undefined,
            aliases: Array.isArray(row.aliases) ? row.aliases.filter((x: unknown) => typeof x === 'string') : [],
            summary: typeof row.summary === 'string' ? row.summary : undefined,
            year: Number.isInteger(row.year) ? row.year : undefined,
            type: 'movie', source: SCRAPER_NAME,
            posters: row.poster ? [new URL(row.poster, API_URL).href] : [], fanarts: [], thumbs: []
        };
    }

    async search(query: string, options: Record<string, any> = {}) {
        const page = Math.max(1, Math.floor(Number(options.page) || 1));
        const pageSize = Math.max(1, Math.min(50, Math.floor(Number(options.pageSize) || 20)));
        const {data} = await networkAxios.get(`${API_URL}/search`, {
            params: {q: query, page, limit: pageSize}, timeout: 15000
        });
        if (!data || !Array.isArray(data.items) || typeof data.hasMore !== 'boolean') {
            throw new Error('Unexpected source search response');
        }
        // This synthetic provider accepts limit and returns an explicit hasMore.
        return {items: data.items.map((row: any) => this.metadata(row)), page, pageSize, hasMore: data.hasMore};
    }

    async scrape(id: string): Promise<ScrapedMetadata | null> {
        const rawId = this.rawId(id);
        let data: any;
        try {
            ({data} = await networkAxios.get(`${API_URL}/works/${encodeURIComponent(rawId)}`, {timeout: 15000}));
        } catch (error: any) {
            if (error?.response?.status === 404) return null;
            throw error;
        }
        const metadata = this.metadata(data);
        if (metadata.uniqueId !== id) throw new Error('Detail response changed the work identity');
        return metadata;
    }
}
