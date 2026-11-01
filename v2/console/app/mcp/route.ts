import { deriveBytes, getNetworkStatus, networkConfig } from "../../lib/rng";

export const dynamic = "force-dynamic";

type RpcRequest = { jsonrpc?: string; id?: string | number | null; method?: string; params?: Record<string, unknown> };
const VERSION = "2026-07-28";

const tools = [
  {
    name: "rng_status",
    description: "Read the current HyperBEAM RNG network, committee, price and independently verified latest round.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "rng_verify_round",
    description: "Fetch and independently verify a retained HyperBEAM RNG round by number.",
    inputSchema: {
      type: "object",
      properties: { round: { type: "integer", minimum: 1 } },
      required: ["round"], additionalProperties: false,
    },
  },
  {
    name: "rng_derive",
    description: "Derive deterministic bytes using the canonical hyperbeam/rng/v1 framing.",
    inputSchema: {
      type: "object",
      properties: {
        seed: { type: "string", minLength: 1, maxLength: 4096 },
        counter: { type: "integer", minimum: 0, default: 0 },
        bytes: { type: "integer", minimum: 1, maximum: 1024, default: 32 },
      },
      required: ["seed"], additionalProperties: false,
    },
  },
  {
    name: "rng_integration_guide",
    description: "Get a current Lua, JavaScript or HTTP integration guide for HyperBEAM RNG.",
    inputSchema: {
      type: "object",
      properties: { language: { type: "string", enum: ["lua", "javascript", "http"] } },
      required: ["language"], additionalProperties: false,
    },
  },
  {
    name: "rng_request_plan",
    description: "Explain which RNG operations need a wallet or test credits before an agent builds a flow.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
] as const;

function textResult(value: unknown, isError = false) {
  return { content: [{ type: "text", text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }], ...(isError ? { isError: true } : {}) };
}

function guide(language: string) {
  const cfg = networkConfig();
  if (language === "lua") return `local rng = require("rng")\n\nrng.on("Loot-Roll", function(stream, ctx)\n  grantLoot(ctx.player, stream:int(1, 6))\nend)\n\nrng.config({ beacon = "${cfg.beacon}" })\nrng.request(msg, { tier = "beacon", on = "Loot-Roll", ctx = { player = msg.From } })`;
  if (language === "javascript") return `const { rng } = connect({ MODE: "mainnet", URL: HYPERBEAM_URL })\n\nconst verified = await rng.verifyRound({\n  publicKey: GROUP_PUBLIC_KEY_HEX,\n  beacon: "${cfg.beacon}",\n  round,\n  signature\n}).then(r => r.json())\n\nconst bytes = await rng.derive({ seed: verified.value, counter: 0, bytes: 32 }).then(r => r.json())`;
  return `GET <hyperbeam-node>/${cfg.beacon}~process@1.0/now/beaconinfo\nGET <hyperbeam-node>/${cfg.beacon}~process@1.0/now/beaconstate\n\nSigning message: hyperbeam/rng/v1|<beacon>|<round>`;
}

async function callTool(name: unknown, args: Record<string, unknown>) {
  if (name === "rng_status") return textResult(await getNetworkStatus());
  if (name === "rng_verify_round") {
    const round = Number(args.round);
    if (!Number.isSafeInteger(round) || round < 1) throw new Error("round must be a positive integer");
    return textResult(await getNetworkStatus(round));
  }
  if (name === "rng_derive") {
    if (typeof args.seed !== "string" || args.seed.length === 0 || args.seed.length > 4096) throw new Error("seed must be a non-empty string of at most 4096 characters");
    const counter = args.counter === undefined ? 0 : Number(args.counter);
    const bytes = args.bytes === undefined ? 32 : Number(args.bytes);
    return textResult({ seed: args.seed, counter, bytes, value: await deriveBytes(args.seed, counter, bytes) });
  }
  if (name === "rng_integration_guide") {
    if (!["lua", "javascript", "http"].includes(String(args.language))) throw new Error("language must be lua, javascript or http");
    return textResult(guide(String(args.language)));
  }
  if (name === "rng_request_plan") return textResult({
    productSurfaces: {
      local: { status: "live", contract: "deterministic and predictable to the sender" },
      threshold: { status: "live", contract: "request-bound 2-of-3 BLS randomness" },
      beacon: { status: "not-deployed", contract: "continuous shared public rounds; the current on-demand Threshold service is not the beacon product" },
      anyHonest: { status: "restoring", contract: "time-lock commit/reveal; not executable on the current testnet" },
      proofExplorer: { status: "live", contract: "independent retained-round verification" },
    },
    device: "One ~rng@1.0 namespace for derivation, BLS verification, and the restored time-lock checks.",
    free: ["local deterministic streams", "round reads", "signature verification", "byte derivation"],
    paid: { operation: "new threshold request", currentTestnetPrice: "3 TEST-RNG", faucet: "100 TEST-RNG per signed request, 1,000 lifetime cap per wallet" },
    recommendedUX: "The AO application process should prepay its beacon balance so end users never manage RNG credits.",
  });
  throw new Error(`unknown tool: ${String(name)}`);
}

export async function POST(request: Request) {
  let rpc: RpcRequest;
  try { rpc = await request.json() as RpcRequest; }
  catch { return Response.json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, { status: 400 }); }
  const id = rpc.id ?? null;
  try {
    let result: unknown;
    if (rpc.method === "server/discover") result = { supportedVersions: [VERSION], capabilities: { tools: {} } };
    else if (rpc.method === "tools/list") result = { tools };
    else if (rpc.method === "tools/call") {
      const params = rpc.params ?? {};
      result = await callTool(params.name, (params.arguments ?? {}) as Record<string, unknown>);
    } else return Response.json({ jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found" } }, { status: 404 });
    return Response.json({ jsonrpc: "2.0", id, result });
  } catch (error) {
    return Response.json({ jsonrpc: "2.0", id, result: textResult(error instanceof Error ? error.message : "Tool failed", true) });
  }
}
