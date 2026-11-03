// Synchronous cleaning example. Preserve titles, years and episode markers.
function clean(input) {
    return input
        .replace(/\.(mkv|mp4|avi|mov)$/i, '')
        .replace(/[._]+/g, ' ')
        .replace(/\b(720p|1080p|2160p|BluRay|WEB-DL)\b/gi, '')
        .replace(/\s+/g, ' ')
        .trim();
}
