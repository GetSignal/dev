export const handler = async (event: any) => {
  try {
    const q = event.queryStringParameters || {};
    const videoId = q.video_id || q.id || "sample";
    const requestedHls = typeof q.hls_url === "string" ? decodeURIComponent(q.hls_url) : undefined;
    const requestedVtt = typeof q.thumbnail_vtt_url === "string" ? decodeURIComponent(q.thumbnail_vtt_url) : undefined;

    // Trim fractional seconds for Apple's JSONDecoder(.iso8601) compatibility
    const createdAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

    const manifest = {
      video_id: String(videoId),
      duration_ms: 183000,
      hls_url: validHls(requestedHls)
        ? (requestedHls as string)
        : "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8",
      poster_url: "https://via.placeholder.com/640x360.jpg?text=Signal",
      thumbnail_vtt_url: validUrl(requestedVtt)
        ? (requestedVtt as string)
        : "https://raw.githubusercontent.com/videojs/videojs-vtt.js/main/docs/example-webvtt.vtt",
      ladder: [
        { height: 240, bitrate: 300000 },
        { height: 360, bitrate: 600000 },
        { height: 480, bitrate: 1100000 },
        { height: 720, bitrate: 2500000 }
      ],
      loudness_lufs: -16.0,
      created_at: createdAt
    };

    return { statusCode: 200, headers: { "content-type": "application/json" }, body: JSON.stringify(manifest) };
  } catch (e) {
    console.error("/v1/manifest error", e);
    return { statusCode: 400, body: JSON.stringify({ error: "bad_request" }) };
  }
};

function validHls(url?: string) {
  if (!url) return false;
  try {
    const u = new URL(url);
    return (u.protocol === "https:" || u.protocol === "http:") && u.pathname.endsWith(".m3u8");
  } catch {
    return false;
  }
}

function validUrl(url?: string) {
  if (!url) return false;
  try {
    const u = new URL(url);
    return u.protocol === "https:" || u.protocol === "http:";
  } catch {
    return false;
  }
}
