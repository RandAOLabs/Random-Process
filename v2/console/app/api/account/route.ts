import { getAccountStatus } from "../../../lib/rng";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const address = new URL(request.url).searchParams.get("address") ?? "";
    return Response.json(await getAccountStatus(address), { headers: { "cache-control": "no-store" } });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "account unavailable" }, { status: 400 });
  }
}
