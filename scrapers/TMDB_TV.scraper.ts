import { BaseScraper } from './base.scraper';
import { ScrapedActor, ScrapedMetadata } from './types';
import axios from 'axios';
import { prisma } from '../db';

// 注意：TMDb 返回的是 JSON，所以这里主要使用 axios
export class TMDB_TVScraper extends BaseScraper {
    public supportedTypes: ('movie' | 'tv')[] = ['tv'];
    private readonly BASE_URL = 'https://api.themoviedb.org/3';
    private readonly IMG_ORIGINAL = 'https://image.tmdb.org/t/p/original';
    private readonly IMG_W500 = 'https://image.tmdb.org/t/p/w500';

    constructor() {
        super('TMDB_TV');
    }

    private pickPreferredTitle(data: any, enData?: any): string {
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
            push(t?.data?.name);
            push(t?.data?.title);
        }

        push(data?.name);
        push(data?.title);
        push(enData?.name);
        push(enData?.title);
        push(data?.original_name);
        push(data?.original_title);

        return out[0] || '';
    }

    /**
     * 内部清洗逻辑：从文件名中提取搜索关键词和年份
     * 参考 Jellyfin: 替换所有非单词字符为空格，以提高 TMDB 匹配率
     */
    private cleanName(name: string): { query: string; year: number | null; season: number | null; episode: number | null } {
        if (!name) return { query: "", year: null, season: null, episode: null };

        let cleaned = name.replace(/\.(mp4|mkv|avi|wmv|iso|ts|flv)$/i, '');
        cleaned = cleaned.replace(/[\._]/g, ' ');

        // 提取年份
        let year: number | null = null;
        const yearMatch = cleaned.match(/\b((?:19|20)\d{2})\b/);
        if (yearMatch) year = parseInt(yearMatch[1]);

        let season: number | null = null;
        let episode: number | null = null;

        // 提取剧集信息
        // 1. SxxExx
        const sxeMatch = cleaned.match(/s(\d{1,2})e(\d{1,3})/i);
        if (sxeMatch) {
            season = parseInt(sxeMatch[1]);
            episode = parseInt(sxeMatch[2]);
        } else {
            // 2. 第xx季 第xx集 / 第xx集
            const seqMatch = cleaned.match(/第\s?(\d{1,2})\s?季/);
            if (seqMatch) season = parseInt(seqMatch[1]);

            const epMatch = cleaned.match(/(?:ep?|第)\s?(\d{1,3})\s?(?:集|话|期)/i);
            if (epMatch) {
                episode = parseInt(epMatch[1]);
                if (!season) season = 1; // 默认为第一季
            }
        }

        // 切除剧集信息 (SxxExx, Ep, 第xx集) 之后的内容
        const seRegex = /(?:s\d{1,2}e\d{1,3}|ep?\d{1,3}|第\s?\d{1,3}\s?[季集话])/i;
        const seMatch = cleaned.match(seRegex);
        if (seMatch) cleaned = cleaned.split(seMatch[0])[0];

        // 移除括号和常见杂质
        cleaned = cleaned.replace(/\[.*?\]|\(.*?\)|【.*?】/g, ' ');

        // 参考 Jellyfin TmdbUtils.CleanName: 替换连续的非字母数字字符为单个空格
        cleaned = cleaned.replace(/[^\w\s\u4e00-\u9fa5]/gi, ' ').replace(/\s+/g, ' ').trim();

        return {
            query: cleaned,
            year,
            season,
            episode
        };
    }

    /**
     * 获取 API KEY (从 Prisma 配置读取)
     */
    private async getApiKey(): Promise<string> {
        try {
            // @ts-ignore: 假设全局有 prisma 实例
            if (typeof prisma !== 'undefined') {
                const config = await (prisma as any).setting.findUnique({ where: { key: 'custom_configs' } });
                const items = JSON.parse(config?.value || '[]');
                return items.find((c: any) => c.key === 'TMDB_API_KEY')?.value || '';
            }
            return process.env.TMDB_API_KEY || '';
        } catch (e) {
            return '';
        }
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

    private buildActorProfile(base: any, detail?: any): ScrapedActor {
        const role = Array.isArray(base?.roles) && base.roles.length > 0 ? (base.roles[0]?.character || '') : '';
        const profilePath = detail?.profile_path || base?.profile_path || '';
        const aliases = Array.isArray(detail?.also_known_as) ? detail.also_known_as.filter(Boolean) : [];
        const intro = (detail?.biography || '').trim();
        const images = Array.isArray(detail?.images?.profiles)
            ? detail.images.profiles.slice(0, 8).map((p: any) => `${this.IMG_W500}${p.file_path}`)
            : [];

        return {
            id: String(base?.id || ''),
            name: base?.name || '',
            role,
            image: profilePath ? `${this.IMG_ORIGINAL}${profilePath}` : '',
            images,
            altName: aliases[0] || undefined,
            aliases,
            nationality: detail?.place_of_birth || '',
            bornDate: detail?.birthday || '',
            intro,
            url: base?.id ? `https://www.themoviedb.org/person/${base.id}` : undefined
        };
    }

    /**
     * 获取分级信息 (参考 Jellyfin)
     */
    private getOfficialRating(contentRatings: any, countryCode: string): string {
        const results = contentRatings?.results || [];
        const preferred = results.find((r: any) => r.iso_3166_1 === countryCode);
        const us = results.find((r: any) => r.iso_3166_1 === 'US');
        const fallback = results[0];

        const rating = preferred || us || fallback;
        if (!rating) return '';

        // 格式化输出，如 US:TV-MA 或 DE:FSK 16
        const prefix = rating.iso_3166_1 === 'US' ? '' : `${rating.iso_3166_1}-`;
        return `${prefix}${rating.rating}`;
    }

    /**
     * 实现 search 接口
     */
    async search(query: string): Promise<ScrapedMetadata[]> {
        const apiKey = await this.getApiKey();
        if (!apiKey) return [];

        // 0. 快速匹配: 如果查询本身就是 ID (例如 tv_12345 或 tv_12345_S1_E1)
        // 支持格式: tv_12345, tv_12345_S1_E1
        const idMatch = query.trim().match(/^(?:tv_)?(\d+)(?:_S(\d+)_E(\d+))?$/i);
        if (idMatch) {
            const id = idMatch[1];
            const season = idMatch[2];
            const episode = idMatch[3];

            const uniqueId = season && episode ? `tv_${id}_S${season}_E${episode}` : `tv_${id}`;
            const title = season && episode ? `ID: ${id} - S${season}E${episode}` : `TMDB ID: ${id}`;

            console.log(`[TMDB_TV] ⚡️ Direct ID detected, skipping search: ${uniqueId}`);

            return [{
                uniqueId: uniqueId,
                title: title,
                source: 'TMDB_TV',
                posters: [], // 详情页会自动获取
                fanarts: [],
                thumbs: [],
                year: 0
            }];
        }

        const { query: cleanQuery, year, season, episode } = this.cleanName(query);
        if (!cleanQuery) return [];

        console.log(`[TMDB_TV] 🔍 Searching: "${cleanQuery}" ${year ? `(${year})` : ''} ${season ? `S${season}E${episode}` : ''}`);

        try {
            const res = await axios.get(`${this.BASE_URL}/search/tv`, {
                params: {
                    api_key: apiKey,
                    query: cleanQuery,
                    language: 'zh-CN',
                    first_air_date_year: year,
                    include_adult: true
                }
            });

            return res.data.results.map((item: any) => {
                // 如果有具体的季集信息，拼接到 ID 中
                let id = `tv_${item.id}`;
                let title = `${item.name} (${item.first_air_date?.split('-')[0] || '未知'})`;

                if (season && episode) {
                    id += `_S${season}_E${episode}`;
                    title += ` - S${season}E${episode}`;
                }

                return {
                    uniqueId: id,
                    title: title,
                    source: 'TMDB_TV', // 统一使用大写
                    type: 'tv',
                    posters: item.poster_path ? [`${this.IMG_W500}${item.poster_path}`] : [],
                    poster: item.poster_path ? `${this.IMG_W500}${item.poster_path}` : ''
                };
            });
        } catch (e) {
            console.error(`[TMDB_TV] Search error:`, e);
            return [];
        }
    }

    /**
     * 实现 scrape 接口
     */
    async scrape(id: string): Promise<ScrapedMetadata> {
        const apiKey = await this.getApiKey();
        if (!apiKey || !id) throw new Error("Missing API Key or ID");

        // 解析 ID 中的 S/E 信息
        const parts = id.replace('tv_', '').split('_');
        const realId = parts[0];

        // 查找 S 和 E 部分
        let targetSeason: number | null = null;
        let targetEpisode: number | null = null;

        parts.forEach(p => {
            if (p.startsWith('S')) targetSeason = parseInt(p.substring(1));
            if (p.startsWith('E')) targetEpisode = parseInt(p.substring(1));
        });

        const language = 'zh-CN';
        const countryCode = 'CN';

        try {
            console.log(`[TMDB_TV] 🔍 Scraping details for TV ID: ${realId} (Original: ${id})`);

            // 1. 获取全量详情 (包含分级、关键词、外部ID、聚合演职员)
            const res = await axios.get(`${this.BASE_URL}/tv/${realId}`, {
                params: {
                    api_key: apiKey,
                    language: language,
                    append_to_response: 'aggregate_credits,images,external_ids,content_ratings,keywords,translations',
                    include_image_language: `${language},en,null`
                }
            });

            const data = res.data;
            const poster = data.poster_path ? `${this.IMG_ORIGINAL}${data.poster_path}` : '';
            const backdrop = data.backdrop_path ? `${this.IMG_ORIGINAL}${data.backdrop_path}` : '';

            // 2. 并行获取所有季度详情 (zh-CN)
            // Keep season 0 (Specials) so clients can render missing specials placeholders.
            const seasons = (data.seasons || []).filter((s: any) => typeof s?.season_number === 'number' && s.season_number >= 0);
            console.log(`[TMDB_TV] Series: ${data.name}, Seasons: ${seasons.length}`);

            const getSeasonPromises = (lang: string) => seasons.map((s: any) =>
                axios.get(`${this.BASE_URL}/tv/${realId}/season/${s.season_number}`, {
                    params: { api_key: apiKey, language: lang }
                }).then(r => ({ season: s.season_number, data: r.data })).catch(() => ({ season: s.season_number, data: null }))
            );

            // Fetch CN seasons
            const cnSeasonResults = await Promise.all(getSeasonPromises(language));

            // 检查由于缺少翻译导致的空简介，如有必要获取英文 Fallback
            let enData: any = null;
            let enSeasonResults: any[] = [];

            const needsFallback = !data.overview || cnSeasonResults.some(r => r.data && r.data.episodes && r.data.episodes.some((e: any) => !e.overview));

            if (needsFallback) {
                console.log(`[TMDB_TV] ⚠️ Missing translations detected. Fetching English fallback for ${data.name}...`);
                try {
                    const enRes = await axios.get(`${this.BASE_URL}/tv/${realId}`, {
                        params: { api_key: apiKey, language: 'en-US' }
                    });
                    enData = enRes.data;
                    enSeasonResults = await Promise.all(getSeasonPromises('en-US'));
                } catch (e) {
                    console.warn(`[TMDB_TV] English fallback failed:`, e);
                }
            }

            // Merge Data
            const finTitle = this.pickPreferredTitle(data, enData);
            const finOverview = data.overview || enData?.overview || '';
            const finBackdrop = backdrop || (enData?.backdrop_path ? `${this.IMG_ORIGINAL}${enData.backdrop_path}` : '');

            // Process Episodes with Merge
            const allEpisodes = cnSeasonResults.flatMap(r => {
                const cnEps = r.data?.episodes || [];
                const enEps = enSeasonResults.find(er => er.season === r.season)?.data?.episodes || [];

                return cnEps.map((ep: any) => {
                    const enEp = enEps.find((e: any) => e.episode_number === ep.episode_number);
                    return {
                        episodeNumber: ep.episode_number,
                        seasonNumber: ep.season_number,
                        title: ep.name || enEp?.name || `Episode ${ep.episode_number}`,
                        summary: ep.overview || enEp?.overview || '',
                        rating: ep.vote_average,
                        airDate: ep.air_date,
                        image: ep.still_path ? `${this.IMG_W500}${ep.still_path}` : (enEp?.still_path ? `${this.IMG_W500}${enEp.still_path}` : '')
                    };
                });
            });

            console.log(`[TMDB_TV] Scraped ${allEpisodes.length} episodes for ${finTitle}. Target S/E: ${targetSeason}/${targetEpisode}`);

            // 3. 增强演职员处理 (Aggregate Credits)
            const cast = data.aggregate_credits?.cast?.slice(0, 15) || [];
            const actorDetails = await Promise.all(cast.map((a: any) => this.fetchPersonDetail(apiKey, Number(a.id))));
            const actorsList: ScrapedActor[] = cast.map((a: any, idx: number) => this.buildActorProfile(a, actorDetails[idx] || undefined)).filter((a: ScrapedActor) => !!a.name);
            const actors = cast.map((a: any) => {
                const role = a.roles?.[0]?.character || '';
                return role ? `${a.name} (饰 ${role})` : a.name;
            });

            // 4. 其它字段映射 (参考 Jellyfin)
            const directors = data.created_by?.map((c: any) => c.name) || [];
            const studios = data.networks?.map((n: any) => n.name) || [];
            const tags = data.keywords?.results?.map((k: any) => k.name) || [];
            const officialRating = this.getOfficialRating(data.content_ratings, countryCode);

            // 如果指定了具体集数，使用该集的标题和简介
            let displayTitle = finTitle;
            let displaySummary = finOverview;
            let displayPoster = poster ? [poster] : [];

            if (targetSeason && targetEpisode) {
                const ep = allEpisodes.find((e: any) => e.seasonNumber === targetSeason && e.episodeNumber === targetEpisode);
                if (ep) {
                    displayTitle = `Episode ${ep.episodeNumber} ${ep.title ? '- ' + ep.title : ''}`;
                    displaySummary = ep.summary || displaySummary;
                    if (ep.image) {
                        // 可选：把单集封面加到海报列表首位
                        displayPoster = [ep.image, ...displayPoster];
                    }
                }
            }

            return {
                uniqueId: id, // Keep original ID (with S/E suffix if present) to maintain uniqueness
                title: displayTitle,
                originalTitle: data.original_name,
                year: parseInt(data.first_air_date?.split('-')[0]) || 0,
                summary: displaySummary,
                rating: data.vote_average || 0,
                type: 'tv',
                directors,
                actors,
                actorsList,
                genres: data.genres?.map((g: any) => g.name) || [],
                posters: displayPoster,
                fanarts: finBackdrop ? [finBackdrop] : [],
                thumbs: data.poster_path ? [`${this.IMG_W500}${data.poster_path}`] : [],
                source: 'TMDB_TV',
                episodes: allEpisodes,
                seasons: seasons.map((s: any) => ({
                    seasonNumber: s.season_number,
                    title: s.name,
                    summary: s.overview,
                    poster: s.poster_path ? `${this.IMG_W500}${s.poster_path}` : '',
                    airDate: s.air_date,
                    episodeCount: s.episode_count,
                    rating: s.vote_average
                })),
                supportsVideo: false,
                // 新增字段
                studios,
                tags,
                officialRating,
                imdbId: data.external_ids?.imdb_id || '',
                tmdbId: data.id?.toString() || ''
            };
        } catch (err: any) {
            console.error(`[TMDB_TV] Scrape failed: ${err.message}`);
            throw err;
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
