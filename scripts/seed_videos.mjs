import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";

const REGION = process.env.AWS_REGION || "us-east-1";
const TABLE = process.env.VIDEOS_TABLE; // e.g., signal-dev-videos
if (!TABLE) {
  console.error("Set VIDEOS_TABLE env var to your DynamoDB table name");
  process.exit(1);
}

const ddb = new DynamoDBClient({ region: REGION });

const nowIso = new Date().toISOString();
const dayBucket = nowIso.substring(0, 10); // YYYY-MM-DD

const items = [
  {
    video_id: "a1",
    media_manifest_url: "https://cdn.example.com/vod/a1/v7/media_manifest.json",
    owner_id: "u1",
    handle: "@alex",
    likes: 1200,
    comments: 80,
    shares: 10,
    engagement: 987.0,
  },
  {
    video_id: "a2",
    media_manifest_url: "https://cdn.example.com/vod/a2/v5/media_manifest.json",
    owner_id: "u2",
    handle: "@mike",
    likes: 540,
    comments: 21,
    shares: 9,
    engagement: 432.5,
  },
  {
    video_id: "a3",
    media_manifest_url: "https://cdn.example.com/vod/a3/v3/media_manifest.json",
    owner_id: "u3",
    handle: "@sam",
    likes: 220,
    comments: 15,
    shares: 4,
    engagement: 188.2,
  }
];

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

