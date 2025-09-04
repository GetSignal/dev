import { DynamoDBClient, QueryCommand, ScanCommand } from "@aws-sdk/client-dynamodb";

const ddb = new DynamoDBClient({});
const TABLE = process.env.VIDEOS_TABLE!;

function pickExplorationRate(): number {
  const min = Number(process.env.EXPLORATION_MIN ?? "0.10");
  const max = Number(process.env.EXPLORATION_MAX ?? "0.20");
  return min + Math.random() * (max - min);
}

export const handler = async (event: any) => {
  try {
    // Try trending query (GSI2: day_bucket / -engagement_score). Fallback to Scan if index missing.
    const today = new Date().toISOString().substring(0, 10);
    let itemsResp;
    try {
      itemsResp = await ddb.send(new QueryCommand({
        TableName: TABLE,
        IndexName: "gsi2_day_engagement",
        KeyConditionExpression: "day_bucket = :d",
        ExpressionAttributeValues: { ":d": { S: today } },
        ScanIndexForward: false,
        Limit: 20,
      }));
    } catch (_e) {
      itemsResp = await ddb.send(new ScanCommand({ TableName: TABLE, Limit: 20 }));
    }

    const items = (itemsResp.Items ?? []).map((it) => ({
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
