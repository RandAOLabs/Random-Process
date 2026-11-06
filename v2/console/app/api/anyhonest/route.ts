import { getAnyHonestStatus } from "../../../lib/rng";

export const dynamic = "force-dynamic";

export async function GET() {
  try { return Response.json(await getAnyHonestStatus(), { headers: { "cache-control": "no-store" } }); }
  catch (error) { return Response.json({ error: error instanceof Error ? error.message : "Any-Honest status unavailable" }, { status: 502 }); }
}
