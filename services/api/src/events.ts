import { FirehoseClient, PutRecordBatchCommand } from "@aws-sdk/client-firehose";

const firehose = new FirehoseClient({});
const STREAM = process.env.FIREHOSE_STREAM!;

export const handler = async (event: any) => {
  try {
    const isHttpApiV2 = !!event.requestContext;
    const body = isHttpApiV2 && event.body ? JSON.parse(event.body) : event;

    const payload = Buffer.from(JSON.stringify({
      ts: Date.now(),
      // pass through envelope as-is for lake
      body,
    }) + "\n");

    await firehose.send(new PutRecordBatchCommand({
      DeliveryStreamName: STREAM,
      Records: [{ Data: payload }],
    }));

    return { statusCode: 200, headers: { "content-type": "application/json" }, body: JSON.stringify({ ok: true }) };
  } catch (e) {
    console.error("/v1/events error", e);
    return { statusCode: 400, body: JSON.stringify({ error: "bad_request" }) };
  }
};
