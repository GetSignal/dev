import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";

const REGION = process.env.AWS_REGION || "us-east-1";
const TABLE = process.env.VIDEOS_TABLE; // e.g., signal-dev-videos
if (!TABLE) {
  console.error("Set VIDEOS_TABLE env var to your DynamoDB table name");
  process.exit(1);
}

const ddb = new DynamoDBClient({ region: REGION });

const nowIso = new Date().toISOString();
const dayBucket = (process.env.DAY_BUCKET || nowIso.substring(0, 10)); // YYYY-MM-DD, override with DAY_BUCKET if set

const apiBase = process.env.API_BASE_URL;
const HLS_URL = process.env.HLS_URL;
const VTT_URL = process.env.VTT_URL;
const HLS_MAP = process.env.HLS_MAP; // JSON: {"v1":"https://...m3u8","v2":"https://...m3u8"}
const HLS_LIST = process.env.HLS_LIST; // Comma or newline separated list of HLS URLs

function manifestUrlFor(id, hlsOverride) {
  if (!apiBase) return null;
  const params = new URLSearchParams({ video_id: id });
  if (hlsOverride) params.set("hls_url", encodeURIComponent(hlsOverride));
  else if (HLS_URL) params.set("hls_url", encodeURIComponent(HLS_URL));
  if (VTT_URL) params.set("thumbnail_vtt_url", encodeURIComponent(VTT_URL));
  return `${apiBase}/v1/manifest?${params.toString()}`;
}

let items = [];

if (HLS_MAP) {
  try {
    const map = JSON.parse(HLS_MAP);
    const entries = Object.entries(map);
    items = entries.map(([id, url], idx) => ({
      video_id: String(id),
      media_manifest_url: manifestUrlFor(String(id), url) || url,
      owner_id: `u${idx + 10}`,
      handle: `@auto${idx + 1}`,
      likes: 100 + idx * 10,
      comments: 10 + idx,
      shares: 5 + Math.floor(idx / 2),
      engagement: 100 + idx * 50,
    }));
  } catch (e) {
    console.error("Invalid HLS_MAP JSON:", e.message);
    process.exit(1);
  }
} else if (HLS_LIST) {
  const urls = HLS_LIST.split(/\n|,/).map(s => s.trim()).filter(Boolean);
  items = urls.map((url, idx) => ({
    video_id: `v${idx + 1}`,
    media_manifest_url: manifestUrlFor(`v${idx + 1}`, url) || url,
    owner_id: `u${idx + 10}`,
    handle: `@auto${idx + 1}`,
    likes: 100 + idx * 10,
    comments: 10 + idx,
    shares: 5 + Math.floor(idx / 2),
    engagement: 100 + idx * 50,
  }));
} else {
  items = [
    {
      video_id: "a1",
      media_manifest_url: manifestUrlFor("a1") || "https://cdn.example.com/vod/a1/v7/media_manifest.json",
      owner_id: "u1",
      handle: "@alex",
      likes: 1200,
      comments: 80,
      shares: 10,
      engagement: 987.0,
    },
    {
      video_id: "a2",
      media_manifest_url: manifestUrlFor("a2") || "https://cdn.example.com/vod/a2/v5/media_manifest.json",
      owner_id: "u2",
      handle: "@mike",
      likes: 540,
      comments: 21,
      shares: 9,
      engagement: 432.5,
    },
    {
      video_id: "a3",
      media_manifest_url: manifestUrlFor("a3") || "https://cdn.example.com/vod/a3/v3/media_manifest.json",
      owner_id: "u3",
      handle: "@sam",
      likes: 220,
      comments: 15,
      shares: 4,
      engagement: 188.2,
    }
  ];
}

for (const it of items) {
  const put = new PutItemCommand({
    TableName: TABLE,
    Item: {
      video_id: { S: it.video_id },
      owner_id: { S: it.owner_id },
      "-created_at": { S: nowIso },
      day_bucket: { S: dayBucket },
      "-engagement_score": { N: String(it.engagement) },
      media_manifest_url: { S: it.media_manifest_url },
      handle: { S: it.handle },
      likes: { N: String(it.likes) },
      comments: { N: String(it.comments) },
      shares: { N: String(it.shares) }
    }
  });
  await ddb.send(put);
  console.log("Seeded", it.video_id);
}

console.log("Done.");
