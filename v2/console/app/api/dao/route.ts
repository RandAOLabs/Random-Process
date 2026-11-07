import { getDaoStake, getGovernanceStatus } from "../../../lib/rng";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const address = new URL(request.url).searchParams.get("address");
  try {
    const body = address ? await getDaoStake(address) : await getGovernanceStatus();
    return Response.json(body, { headers: { "cache-control": "no-store" } });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "DAO status unavailable" }, { status: address ? 400 : 502 });
  }
}
