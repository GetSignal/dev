import { DynamoDBClient, QueryCommand } from "@aws-sdk/client-dynamodb";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { createClient } from "redis";

const ddb = new DynamoDBClient({});
const secrets = new SecretsManagerClient({});
const TABLE = process.env.VIDEOS_TABLE!;
const FALLBACK_DAYS = Math.max(1, Number(process.env.FALLBACK_DAYS ?? "5"));
const TRENDING_SET_KEY = process.env.TRENDING_SET_KEY ?? "trending:v1";
const TRENDING_SIZE = Math.max(100, Number(process.env.TRENDING_SIZE ?? "1000"));
const TRENDING_REDIS_URL = process.env.TRENDING_REDIS_URL!;
const TRENDING_REDIS_AUTH_TOKEN = process.env.TRENDING_REDIS_AUTH_TOKEN;
const TRENDING_REDIS_AUTH_SECRET_ARN = process.env.TRENDING_REDIS_AUTH_SECRET_ARN;

function dayMinus(n: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().substring(0, 10);
}

export const handler = async () => {
  let password = TRENDING_REDIS_AUTH_TOKEN;
  if (TRENDING_REDIS_AUTH_SECRET_ARN) {
    const resp = await secrets.send(new GetSecretValueCommand({ SecretId: TRENDING_REDIS_AUTH_SECRET_ARN }));
    password = resp.SecretString || (resp.SecretBinary ? Buffer.from(resp.SecretBinary as any).toString("utf8") : undefined);
  }
  const redis = createClient({ url: TRENDING_REDIS_URL, socket: { tls: TRENDING_REDIS_URL.startsWith("rediss://") }, password });
  redis.on("error", (err) => console.error("Redis error", err));
  await redis.connect();
  try {
    const items: { id: string; score: number }[] = [];
    const seen = new Set<string>();
    for (let i = 0; i < FALLBACK_DAYS && items.length < TRENDING_SIZE; i++) {
      const day = i === 0 ? new Date().toISOString().substring(0, 10) : dayMinus(i);
      const resp = await ddb.send(
        new QueryCommand({
          TableName: TABLE,
          IndexName: "gsi2_day_engagement",
          KeyConditionExpression: "day_bucket = :d",
          ExpressionAttributeValues: { ":d": { S: day } },
          ScanIndexForward: false,
          Limit: TRENDING_SIZE,
          ProjectionExpression: "video_id, -engagement_score",
        })
      );
      for (const it of resp.Items ?? []) {
        const id = it.video_id?.S ?? "";
        const score = Number(it["-engagement_score"]?.N ?? 0);
        if (!id || seen.has(id)) continue;
        seen.add(id);
        items.push({ id, score });
        if (items.length >= TRENDING_SIZE) break;
      }
    }
    // Rebuild ZSET efficiently: use MULTI, delete+add
    const multi = redis.multi();
    multi.del(TRENDING_SET_KEY);
    if (items.length) {
      // Redis v4 supports ZADD with score/member pairs
      for (const { id, score } of items) {
        multi.zAdd(TRENDING_SET_KEY, [{ score, value: id }]);
      }
    }
    await multi.exec();
    console.info(`trendingWriter updated ${TRENDING_SET_KEY} with ${items.length} items`);
  } finally {
    await redis.quit();
  }
  return { ok: true };
};
