import { BaseScraper } from './base.scraper';
import { ScrapedActor, ScrapedMetadata } from './types';
import axios from 'axios';
import { prisma } from '../db';

export class TMDBScraper extends BaseScraper {
    public supportedTypes: ('movie' | 'tv')[] = ['movie'];
    private readonly BASE_URL = "https://api.themoviedb.org/3";
    private readonly IMAGE_BASE_URL = "https://image.tmdb.org/t/p/original";
    private readonly IMG_W500 = "https://image.tmdb.org/t/p/w500";

    constructor() {
        super('TMDB');
    }

    private pickPreferredTitle(data: any): string {
        const out: string[] = [];
        const push = (v: any) => {
            if (typeof v !== 'string') return;
            const s = v.trim();
            if (!s) return;
            if (!out.includes(s)) out.push(s);
        };

        const translations = Array.isArray(data?.translations?.translations) ? data.translations.translations : [];
        const zhTranslations = translations
            .filter((t: any) => t?.iso_639_1 === 'zh')
            .sort((a: any, b: any) => {
                const rank = (iso: string) => {
                    if (iso === 'CN') return 0;
                    if (iso === 'TW') return 1;
                    if (iso === 'HK') return 2;
                    if (iso === 'SG') return 3;
                    return 9;
                };
                return rank(a?.iso_3166_1 || '') - rank(b?.iso_3166_1 || '');
            });

        for (const t of zhTranslations) {
            push(t?.data?.title);
            push(t?.data?.name);
        }

        push(data?.title);
        push(data?.name);
        push(data?.original_title);
        push(data?.original_name);
        return out[0] || '';
    }

    private async getApiKey(): Promise<string> {
        try {
            // @ts-ignore
            if (typeof prisma !== 'undefined') {
                const configSetting = await (prisma as any).setting.findUnique({ where: { key: "custom_configs" } });
                if (configSetting && configSetting.value) {
                    const configs = JSON.parse(configSetting.value);
                    if (Array.isArray(configs)) {
                        const found = configs.find((c: any) => c.key === "TMDB_API_KEY");
                        if (found && found.value) return found.value;
                    }
                }
            }
            return process.env.TMDB_API_KEY || "";
        } catch (e) { return ""; }
    }

    private async fetchPersonDetail(apiKey: string, personId: number): Promise<any | null> {
        try {
            const res = await axios.get(`${this.BASE_URL}/person/${personId}`, {
                params: {
                    api_key: apiKey,
                    language: 'zh-CN',
                    append_to_response: 'images,external_ids',
                    include_image_language: 'zh-CN,en,null'
                }
            });
            return res.data;
        } catch (e) {
            return null;
        }
    }

    private async fetchMovieCredits(apiKey: string, movieId: string): Promise<any[]> {
        try {
            const res = await axios.get(`${this.BASE_URL}/movie/${movieId}/credits`, {
                params: { api_key: apiKey }
            });
            return Array.isArray(res.data?.cast) ? res.data.cast : [];
        } catch (e) {
            return [];
        }
    }

    private buildActorProfile(base: any, detail?: any): ScrapedActor {
        const profilePath = detail?.profile_path || base?.profile_path || '';
        const aliases = Array.isArray(detail?.also_known_as) ? detail.also_known_as.filter(Boolean) : [];
        const intro = (detail?.biography || '').trim();
        const images = Array.isArray(detail?.images?.profiles)
            ? detail.images.profiles.slice(0, 8).map((p: any) => `${this.IMG_W500}${p.file_path}`)
            : [];

        return {
            id: String(base?.id || ''),
            name: base?.name || '',
            role: base?.character || '',
            image: profilePath ? `${this.IMAGE_BASE_URL}${profilePath}` : '',
            images,
            altName: aliases[0] || undefined,
            aliases,
            nationality: detail?.place_of_birth || '',
            bornDate: detail?.birthday || '',
            intro,
            url: base?.id ? `https://www.themoviedb.org/person/${base.id}` : undefined
        };
    }

    async search(query: string, options?: any): Promise<ScrapedMetadata[]> {
        const apiKey = await this.getApiKey();
        if (!apiKey) return [];
        const endpoint = "/search/movie";
        try {
            const res = await axios.get(`${this.BASE_URL}${endpoint}`, { params: { api_key: apiKey, query, language: "zh-CN" } });
            return (res.data.results || []).map((item: any) => ({
                uniqueId: item.id.toString(),
                title: `${item.title || item.name} (${(item.release_date || item.first_air_date)?.split("-")[0] || "N/A"})`,
                source: "TMDB",
                type: "movie",
                poster: item.poster_path ? `${this.IMG_W500}${item.poster_path}` : ""
            }));
        } catch (e) { return []; }
    }

    async scrape(id: string, options?: any): Promise<ScrapedMetadata> {
        const apiKey = await this.getApiKey();
        if (!apiKey) throw new Error("Missing API Key");

        const realId = id.toString().replace(/^(tv|movie)_/, '').split('_')[0];
        console.log(`[Script:TMDB] Raw ID: ${id}, Real ID: ${realId}`);

        const scrapeOne = async (): Promise<ScrapedMetadata> => {
            console.log(`[Script:TMDB] Scraping movie with internal ID: ${realId}`);
            const endpoint = `/movie/${realId}`;
            const res = await axios.get(`${this.BASE_URL}${endpoint}`, {
                params: {
                    api_key: apiKey,
                    language: "zh-CN",
                    append_to_response: "credits,external_ids,images,content_ratings,translations"
                }
            });
            const data = res.data;
            const poster = data.poster_path ? `${this.IMAGE_BASE_URL}${data.poster_path}` : "";
            const backdrop = data.backdrop_path ? `${this.IMAGE_BASE_URL}${data.backdrop_path}` : "";
            let cast = data.credits?.cast || [];
            if (!Array.isArray(cast) || cast.length === 0) {
                cast = await this.fetchMovieCredits(apiKey, realId);
            }
            cast = cast.slice(0, 12);
            const actorDetails = await Promise.all(cast.map((a: any) => this.fetchPersonDetail(apiKey, Number(a.id))));
            const actorsList: ScrapedActor[] = cast.map((a: any, idx: number) => this.buildActorProfile(a, actorDetails[idx] || undefined)).filter((a: ScrapedActor) => !!a.name);

            return {
                uniqueId: id.toString(),
                title: this.pickPreferredTitle(data),
                originalTitle: data.original_title || data.original_name,
                year: parseInt((data.release_date || data.first_air_date)?.split("-")[0]) || 0,
                summary: data.overview || "",
                rating: data.vote_average || 0,
                directors: (data.credits?.crew?.filter((p: any) => p.job === "Director").map((d: any) => d.name) || []),
                actors: cast.map((a: any) => a.character ? `${a.name} (饰 ${a.character})` : a.name),
                actorsList,
                genres: data.genres?.map((g: any) => g.name) || [],
                posters: poster ? [poster] : [],
                fanarts: backdrop ? [backdrop] : [],
                thumbs: poster ? [poster] : [],
                source: "TMDB",
                type: "movie",
                episodes: [],
                supportsVideo: false
            };
        };

        try {
            return await scrapeOne();
        } catch (e: any) {
            console.error('[Script:TMDB] Scrape failed:', e.message);
            throw e;
        }
    }

    async searchActor(query: string): Promise<ScrapedActor[]> {
        const apiKey = await this.getApiKey();
        if (!apiKey || !query) return [];
        try {
            const res = await axios.get(`${this.BASE_URL}/search/person`, {
                params: { api_key: apiKey, query, language: 'zh-CN', include_adult: true }
            });
            const list = res.data?.results || [];
            return list.slice(0, 15).map((p: any) => this.buildActorProfile(p));
        } catch {
            return [];
        }
    }

    async scrapeActor(id: string): Promise<ScrapedActor | null> {
        const apiKey = await this.getApiKey();
        if (!apiKey || !id) return null;
        const personId = String(id).replace(/^person_/, '').trim();
        if (!/^\d+$/.test(personId)) return null;
        const detail = await this.fetchPersonDetail(apiKey, Number(personId));
        if (!detail) return null;
        return this.buildActorProfile({ id: personId, name: detail.name, profile_path: detail.profile_path }, detail);
    }
}
