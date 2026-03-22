/**
 * Built-in movie cleaning script.
 */
function clean(name) {
  if (!name) return "";

  // 1. Remove file extension
  let cleaned = name.replace(/\.(mp4|mkv|avi|wmv|iso|mov|ts|flv)$/i, '');

  // 2. Normalize common separators
  cleaned = cleaned.replace(/[\._]/g, ' ');

  // 3. Remove bracketed content
  const brackets = [
    /\[.*?\]/g,
    /\(.*?\)/g,
    /【.*?】/g
  ];
  let yearInBracket = null;
  const yearMatchInside = name.match(/[\(\[【](\d{4})[\)\]】]/);
  if (yearMatchInside) yearInBracket = yearMatchInside[1];

  brackets.forEach(re => cleaned = cleaned.replace(re, ' '));

  // 4. Remove common movie noise
  const movieNoise = [
    '2160P', '1080P', '720P', '4K', '8K', 'HDR', '10BIT', 'DV', 'REMUX',
    'BLURAY', 'BD-RIP', 'WEBRIP', 'WEB-DL', 'HDTV', 'HC',
    'X264', 'X265', 'H264', 'H265', 'HEVC', 'AVC',
    'DTS', 'DTS-HD', 'TRUEHD', 'ATMOS', 'DD5 1', 'DDP5 1', 'AAC', 'AC3',
    'CHINESE', 'ENGLISH', 'CHS', 'CHT', 'SUBBED', 'UNCUT', 'DIRECTORS CUT'
  ];
  movieNoise.forEach(word => {
    const re = new RegExp('\\b' + word + '\\b', 'gi');
    cleaned = cleaned.replace(re, ' ');
  });

  // 5. Extract year
  const yearMatch = cleaned.match(/\b((?:19|20)\d{2})\b/);
  let year = yearInBracket || (yearMatch ? yearMatch[1] : "");
  let title = cleaned;

  if (yearMatch) {
    title = cleaned.split(yearMatch[0])[0];
  }

  // 6. Trim trailing noise
  title = title.trim()
               .replace(/[-_ \.]+$/, '')
               .replace(/\s+/g, ' ');

  return title;
}
