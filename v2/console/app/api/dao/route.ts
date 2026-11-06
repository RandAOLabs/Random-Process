import { getGovernanceStatus } from "../../../lib/rng";

export const dynamic = "force-dynamic";

export async function GET() {
  try { return Response.json(await getGovernanceStatus(), { headers: { "cache-control": "no-store" } }); }
  catch (error) { return Response.json({ error: error instanceof Error ? error.message : "DAO status unavailable" }, { status: 502 }); }
}
