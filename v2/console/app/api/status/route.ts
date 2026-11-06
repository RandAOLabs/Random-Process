import { getNetworkStatus } from "../../../lib/rng";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const rawRound = url.searchParams.get("round");
    const round = rawRound === null ? undefined : Number(rawRound);
    if (round !== undefined && (!Number.isSafeInteger(round) || round < 1)) {
      return Response.json({ error: "round must be a positive integer" }, { status: 400 });
    }
    return Response.json(await getNetworkStatus(round), { headers: { "cache-control": "no-store" } });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "status unavailable" }, { status: 502 });
  }
}
