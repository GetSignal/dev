import { DynamoDBClient, QueryCommand, BatchGetItemCommand } from "@aws-sdk/client-dynamodb";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { createClient, RedisClientType } from "redis";

const ddb = new DynamoDBClient({});
const secrets = new SecretsManagerClient({});
const TABLE = process.env.VIDEOS_TABLE!;
const FEED_LIMIT = Number(process.env.FEED_LIMIT ?? "20");
const FALLBACK_DAYS = Math.max(1, Number(process.env.FALLBACK_DAYS ?? "3"));
const TRENDING_REDIS_URL = process.env.TRENDING_REDIS_URL;
const TRENDING_REDIS_AUTH_TOKEN = process.env.TRENDING_REDIS_AUTH_TOKEN;
const TRENDING_REDIS_AUTH_SECRET_ARN = process.env.TRENDING_REDIS_AUTH_SECRET_ARN;

let redisClient: RedisClientType | null = null;
let cachedRedisToken: string | null = null;
async function getRedisAuthToken(): Promise<string | undefined> {
  if (TRENDING_REDIS_AUTH_SECRET_ARN) {
    try {
      if (cachedRedisToken) return cachedRedisToken;
      const resp = await secrets.send(new GetSecretValueCommand({ SecretId: TRENDING_REDIS_AUTH_SECRET_ARN }));
      const token = resp.SecretString || (resp.SecretBinary ? Buffer.from(resp.SecretBinary as any).toString("utf8") : undefined);
      if (token) cachedRedisToken = token;
      if (token) return token;
    } catch (e) {
      console.warn("/v1/feed secret_fetch_failed; falling back to env token");
    }
  }
  return TRENDING_REDIS_AUTH_TOKEN;
}
async function getRedis(): Promise<RedisClientType | null> {
  if (!TRENDING_REDIS_URL) return null;
  if (redisClient) return redisClient;
  try {
    const password = await getRedisAuthToken();
    const client = createClient({ url: TRENDING_REDIS_URL, socket: { tls: TRENDING_REDIS_URL.startsWith("rediss://") }, password });
    client.on("error", (err) => console.error("Redis error", err));
    await client.connect();
    redisClient = client;
    return client;
  } catch (e) {
    console.warn("/v1/feed redis_connect_failed; proceeding without trending", (e as Error)?.message || e);
    return null;
  }
}

function pickExplorationRate(): number {
  const min = Number(process.env.EXPLORATION_MIN ?? "0.10");
  const max = Number(process.env.EXPLORATION_MAX ?? "0.20");
  return min + Math.random() * (max - min);
}

export const handler = async (event: any) => {
  try {
    // Query multi-day window on GSI2 (day_bucket / -engagement_score) to FEED_LIMIT.
    const today = new Date().toISOString().substring(0, 10);

    const queryByDay = async (day: string) =>
      ddb.send(
        new QueryCommand({
          TableName: TABLE,
          IndexName: "gsi2_day_engagement",
          KeyConditionExpression: "day_bucket = :d",
          ExpressionAttributeValues: { ":d": { S: day } },
          ScanIndexForward: false,
          Limit: FEED_LIMIT,
        })
      );

    const dayMinus = (n: number) => {
      const d = new Date();
      d.setUTCDate(d.getUTCDate() - n);
      return d.toISOString().substring(0, 10);
    };
    const dedupe = new Set<string>();
    const collected: any[] = [];
    for (let i = 0; i < FALLBACK_DAYS && collected.length < FEED_LIMIT; i++) {
      const day = i === 0 ? today : dayMinus(i);
      let resp;
      try {
        resp = await queryByDay(day);
      } catch (e) {
        console.error("/v1/feed gsi2 query failed", e);
        break; // do not scan; rely on trending backfill
      }
      for (const it of resp.Items ?? []) {
        const vid = it.video_id?.S ?? "";
        if (!vid || dedupe.has(vid)) continue;
        dedupe.add(vid);
        collected.push(it);
        if (collected.length >= FEED_LIMIT) break;
      }
      if (i > 0 && (resp.Items?.length ?? 0) > 0) {
        console.info(`/v1/feed fallback_prev_day day_minus=${i}`);
      }
    }

    // Trending Redis backfill if needed (no scans in prod path)
    if (collected.length < FEED_LIMIT) {
      try {
        const redis = await getRedis();
        if (redis) {
          const need = FEED_LIMIT - collected.length;
          // Highest rank first (use ZREVRANGE). Adjust if using ascending scores.
          const ids: string[] = await redis.zRange("trending:v1", -need, -1, { REV: true });
          const missing = ids.filter((id) => id && !dedupe.has(id));
          if (missing.length > 0) {
            const keys = missing.map((id) => ({ video_id: { S: id } }));
            // BatchGet in chunks of 100
            for (let i = 0; i < keys.length && collected.length < FEED_LIMIT; i += 100) {
              const batch = keys.slice(i, i + 100);
              const bg = await ddb.send(
                new BatchGetItemCommand({
                  RequestItems: {
                    [TABLE]: {
                      Keys: batch,
                      ProjectionExpression: "video_id, owner_id, handle, media_manifest_url, likes, comments, shares",
                    },
                  },
                })
              );
              const got = bg.Responses?.[TABLE] ?? [];
              for (const it of got) {
                const vid = it.video_id?.S ?? "";
                if (!vid || dedupe.has(vid)) continue;
                dedupe.add(vid);
                collected.push(it);
                if (collected.length >= FEED_LIMIT) break;
              }
            }
            console.info("/v1/feed fallback_trending count=" + (collected.length));
          }
        } else {
          console.warn("/v1/feed no_redis; skipping trending backfill");
        }
      } catch (e) {
        console.error("/v1/feed trending_backfill_error", e);
      }
    }

    const items = collected.map((it) => ({
      video_id: it.video_id?.S ?? "unknown",
      media_manifest_url: it.media_manifest_url?.S ?? "",
      author: { id: it.owner_id?.S ?? "unknown", handle: it.handle?.S ?? "@unknown" },
      stats: { likes: Number(it.likes?.N ?? 0), comments: Number(it.comments?.N ?? 0), shares: Number(it.shares?.N ?? 0) },
    }));

    const body = {
      cursor: null,
      exploration_rate: pickExplorationRate(),
      items,
    };

    return { statusCode: 200, headers: { "content-type": "application/json" }, body: JSON.stringify(body) };
  } catch (e) {
    console.error("/v1/feed error", e);
    return { statusCode: 500, body: JSON.stringify({ error: "internal_error" }) };
  }
};
