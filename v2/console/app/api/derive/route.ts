import { deriveBytes } from "../../../lib/rng";

export async function POST(request: Request) {
  try {
    const body = await request.json() as { seed?: unknown; counter?: unknown; bytes?: unknown };
    if (typeof body.seed !== "string" || body.seed.length === 0 || body.seed.length > 4096) {
      return Response.json({ error: "seed must be a non-empty string of at most 4096 characters" }, { status: 400 });
    }
    const counter = body.counter === undefined ? 0 : Number(body.counter);
    const bytes = body.bytes === undefined ? 32 : Number(body.bytes);
    return Response.json({ seed: body.seed, counter, bytes, value: await deriveBytes(body.seed, counter, bytes) });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "derivation failed" }, { status: 400 });
  }
}
