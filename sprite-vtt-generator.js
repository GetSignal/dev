// index.js - Sprite + WebVTT generator (Node 18 + sharp)
// Expects frames in s3://BUCKET/ASSET/storyboard/frames/<base>_thumb.NNNNNNN.jpg
// Emits sprites of GRID_WxGRID_H tiles and a storyboard.vtt with #xywh cues

import { S3Client, ListObjectsV2Command, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import sharp from "sharp";

const s3 = new S3Client({});

const GRID_W = parseInt(process.env.GRID_W || "10", 10);     // tiles per row
const GRID_H = parseInt(process.env.GRID_H || "10", 10);     // tiles per column
const TILE_W = parseInt(process.env.TILE_W || "160", 10);
const TILE_H = parseInt(process.env.TILE_H || "90", 10);
const INTERVAL_SEC = parseFloat(process.env.INTERVAL_SEC || "2");
const QUALITY = parseInt(process.env.QUALITY || "80", 10);

export const handler = async (event) => {
  const bucket = process.env.BUCKET;
  const prefix = process.env.FRAMES_PREFIX; // e.g., a1/storyboard/frames/
  const outPrefix = process.env.OUT_PREFIX; // e.g., a1/storyboard/

  // 1) List frames
  const frames = await listAll(bucket, prefix);
  const jpgs = frames.filter(o => o.Key?.endsWith(".jpg")).map(o => o.Key).sort();

  // 2) Load and pack into sprites
  const perSprite = GRID_W * GRID_H;
  const spriteUrls = [];
  for (let i = 0; i < jpgs.length; i += perSprite) {
    const batch = jpgs.slice(i, i + perSprite);
    const cols = GRID_W, rows = Math.ceil(batch.length / GRID_W);
    const sprite = sharp({ create: { width: cols * TILE_W, height: rows * TILE_H, channels: 3, background: { r: 0, g: 0, b: 0 } } });
    const composites = [];
    for (let idx = 0; idx < batch.length; idx++) {
      const key = batch[idx];
      const buf = await getBytes(bucket, key);
      const x = (idx % cols) * TILE_W;
      const y = Math.floor(idx / cols) * TILE_H;
      composites.push({ input: buf, top: y, left: x });
    }
    const composed = await sprite.composite(composites).jpeg({ quality: QUALITY }).toBuffer();
    const spriteIndex = Math.floor(i / perSprite) + 1;
    const outKey = `${outPrefix}sprites_${String(spriteIndex).padStart(4, "0")}.jpg`;
    await putBytes(bucket, outKey, composed, "image/jpeg");
    spriteUrls.push(outKey);
  }

  // 3) Write storyboard.vtt
  const vtt = buildVtt(spriteUrls, INTERVAL_SEC, GRID_W, GRID_H, TILE_W, TILE_H, outPrefix);
  await putBytes(bucket, `${outPrefix}storyboard.vtt`, Buffer.from(vtt, "utf-8"), "text/vtt");

  return { ok: true, sprites: spriteUrls.length };
};

function buildVtt(spriteKeys, stepSec, cols, rows, tileW, tileH, outPrefix) {
  let out = "WEBVTT\n\n";
  let t = 0;
  for (let s = 0; s < spriteKeys.length; s++) {
    const key = spriteKeys[s];
    for (let i = 0; i < cols * rows; i++) {
      const start = toTime(t);
      const end = toTime(t + stepSec);
      const x = (i % cols) * tileW;
      const y = Math.floor(i / cols) * tileH;
      out += `${start} --> ${end}\n`;
      out += `/${key}#xywh=${x},${y},${tileW},${tileH}\n\n`;
      t += stepSec;
    }
  }
  return out;
}

function toTime(sec) {
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = Math.floor(sec % 60);
  const ms = Math.round((sec - Math.floor(sec)) * 1000);
  return `${String(h).padStart(2,"0")}:${String(m).padStart(2,"0")}:${String(s).padStart(2,"0")}.${String(ms).padStart(3,"0")}`;
}

async function listAll(Bucket, Prefix) {
  let out = []; let Token;
  do {
    const res = await s3.send(new ListObjectsV2Command({ Bucket, Prefix, ContinuationToken: Token }));
    out = out.concat(res.Contents || []); Token = res.IsTruncated ? res.NextContinuationToken : undefined;
  } while (Token);
  return out;
}

async function getBytes(Bucket, Key) {
  const res = await s3.send(new GetObjectCommand({ Bucket, Key }));
  return Buffer.from(await res.Body.transformToByteArray());
}
async function putBytes(Bucket, Key, Body, ContentType) {
  await s3.send(new PutObjectCommand({ Bucket, Key, Body, ContentType, CacheControl: "public, max-age=31536000, immutable" }));
}
