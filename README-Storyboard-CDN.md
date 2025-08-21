# Storyboard & CDN Recipe

This folder includes:
- `mediaconvert-storyboard-template.json` — a job template that **adds a FrameCapture File Group** to your HLS job so you get 160x90 JPEG frames every 2s. Use it with a post-step to pack sprites and emit WebVTT (`#xywh`). (MediaConvert doesn't emit sprite sheets directly.)
- `terraform-cloudfront-cache.tf` — CloudFront + S3 setup that serves sprites/VTT with **immutable 1-year caching**.

## Why a post-step?
AWS MediaConvert can output **frame captures** (JPEG) at intervals, but it **doesn't build sprite sheets** or the WebVTT `#xywh` index. Use a lightweight Lambda (example below) to stitch frames into sprite JPGs and write a WebVTT that maps time ranges to sprite `xywh`.

## Minimal Node Lambda (uses `sharp` layer)
- Input: `s3://<bucket>/<asset>/storyboard/frames/` containing `*.jpg` from MediaConvert
- Output: `s3://<bucket>/<asset>/storyboard/sprites_0001.jpg`, `sprites_0002.jpg`, and `storyboard.vtt`

### Handler (sprite-vtt-generator.js)
```bash
# Build zip:
#   npm i sharp
#   zip -r sprite-vtt-generator.zip index.js node_modules
```

## Cache-Control
Use versioned keys (e.g., `/a1/v7/`) and set `Cache-Control: public, max-age=31536000, immutable`. CloudFront policy here also injects that header.
