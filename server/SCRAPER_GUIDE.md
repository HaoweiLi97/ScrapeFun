# scrapeTab Custom Scraper Development Guide

This guide explains how to write custom scraping scripts for the scrapeTab platform.

## Script Structure

Every custom scraper script should implement two main asynchronous functions: `search` and `scrape`.

```javascript
/**
 * @param {string} query - The search term entered by the user.
 * @param {Object} context - Helpers: { fetchHtml, axios, cheerio }
 * @returns {Promise<ScrapedMetadata[]>}
 */
async function search(query, { fetchHtml, axios, cheerio }) {
  // Logic to search for items
}

/**
 * @param {string} id - The unique identifier of the item to scrape.
 * @param {Object} context - Helpers: { fetchHtml, axios, cheerio }
 * @returns {Promise<ScrapedMetadata>}
 */
async function scrape(id, { fetchHtml, axios, cheerio }) {
  // Logic to fetch full details
}

/**
 * @param {string} id - The unique identifier of the item.
 * @param {Object} context - Helpers: { fetchHtml, axios, cheerio }
 * @returns {Promise<string | null>} - The direct video URL or embed URL.
 */
async function getVideoUrl(id, { fetchHtml, axios, cheerio }) {
  // Logic to fetch the real-time video link
}
```

## Available Global Variables & Helpers

- `input`: The current query (for search) or ID (for scrape/video).
- `type`: Either `'search'`, `'scrape'`, or `'video'`, indicating the current mode.
- `axios`: The popular HTTP client for making network requests.
- `cheerio`: A fast, flexible implementation of core jQuery for parsing HTML.
- `fetchHtml(url)`: A helper function that fetches a URL and returns a `cheerio` load instance.
- `fetchHtmlFlareSolverr(url)`: A helper that uses FlareSolverr proxy to bypass Cloudflare protection. Returns a `cheerio` instance.
- `console`: Standard console for debugging (logs appear in the server terminal).

## Data Structure (ScrapedMetadata)

Your functions should return objects following this structure:

| Property | Type | Description | Required |
| :--- | :--- | :--- | :--- |
| `uniqueId` | `string` | A unique ID for the item on that source. | Yes |
| `title` | `string` | The title of the movie or series. | Yes |
| `source` | `string` | The name of your scraper source. | Yes |
| `year` | `number` | Release year. | No |
| `summary` | `string` | A brief plot summary. | No |
| `rating` | `number` | Rating (e.g., 8.5). | No |
| `posters` | `string[]` | Array of image URLs for posters. | No |
| `fanarts` | `string[]` | Array of image URLs for background/fanart. | No |
| `thumbs` | `string[]` | Array of image URLs for thumbnails. | No |
| `directors`| `string[]` | List of directors. | No |
| `actors` | `string[]` | List of actors. | No |
| `genres` | `string[]` | List of genres. | No |
| `supportsVideo`| `boolean` | Set automatically if `getVideoUrl` is defined. | No |

## Example Script

```javascript
async function search(query, { fetchHtml }) {
  const $ = await fetchHtml(`https://example.com/search?q=${encodeURIComponent(query)}`);
  const results = [];
  
  $('.item').each((i, el) => {
    results.push({
      uniqueId: $(el).data('id'),
      title: $(el).find('.title').text(),
      source: 'ExampleSource',
      year: parseInt($(el).find('.year').text()),
      posters: [$(el).find('img').attr('src')]
    });
  });
  
  return results;
}

async function scrape(id, { fetchHtml }) {
  const $ = await fetchHtml(`https://example.com/movie/${id}`);
  
  return {
    uniqueId: id,
    title: $('.main-title').text(),
    summary: $('.desc').text(),
    rating: parseFloat($('.score').text()),
    source: 'ExampleSource',
    posters: [$('.poster').attr('src')],
    fanarts: [$('.backdrop').attr('src')],
    genres: $('.genre').map((i, el) => $(el).text()).get()
  };
}

async function getVideoUrl(id, { fetchHtml }) {
  const $ = await fetchHtml(`https://example.com/movie/${id}/play`);
  // Extraction logic for video URL
  return $('.video-player').attr('data-url'); 
}
```

## Handling Cloudflare Protection

If you encounter `403 Forbidden` errors due to Cloudflare protection, use the `fetchHtmlFlareSolverr` helper instead of `fetchHtml`.

### Example with FlareSolverr
```javascript
async function search(query, { fetchHtmlFlareSolverr }) {
  // Use FlareSolverr helper for sites with Cloudflare protection
  const $ = await fetchHtmlFlareSolverr(`https://protected-site.com/search?q=${encodeURIComponent(query)}`);
  
  const results = [];
  $('.item').each((i, el) => {
    results.push({
      uniqueId: $(el).data('id'),
      title: $(el).find('.title').text(),
      source: 'ProtectedSource'
    });
  });
  
  return results;
}
```

> [!IMPORTANT]
> To use `fetchHtmlFlareSolverr`, you must have a [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) instance running and configured in your `.env` file via `FLARESOLVERR_URL`.

## Best Practices

1. **Error Handling**: Use `try/catch` internally if you want to handle specific site errors gracefully.
2. **Encodings**: Use `encodeURIComponent` when building search URLs.
3. **Async/Await**: Always use `await` for network requests.
4. **Validation**: Ensure `uniqueId` is consistent between `search` and `scrape`.
5. **Video Support Detection**: The platform automatically detects the presence of `getVideoUrl` to enable the "Play" button. Ensure the function is defined clearly (e.g., `async function getVideoUrl(...)`).

## Video Playback Details

The platform supports two types of video URLs in the `getVideoUrl` return value:

- **Direct Video Links**: Any URL ending in `.mp4`, `.m3u8`, etc. These will be played using a standard HTML5 `<video>` tag.
- **Embedded Players (YouTube/Iframe)**: URLs from YouTube or other sites that provide an embed link. These will be rendered within an `<iframe>`.

### Example `getVideoUrl` implementation
```javascript
async function getVideoUrl(id, { fetchHtml }) {
  // Option A: Direct MP4 link
  // return "https://example.com/videos/movie-123.mp4";
  
  // Option B: YouTube Embed
  // return "https://www.youtube.com/embed/dQw4w9WgXcQ";
  
  // Option C: Real extraction
  const $ = await fetchHtml(`https://mysite.com/watch/${id}`);
  const streamUrl = $('source').attr('src');
  return streamUrl;
}
```
