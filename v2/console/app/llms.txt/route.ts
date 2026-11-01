import { networkConfig } from "../../lib/rng";

export const dynamic = "force-dynamic";

export async function GET() {
  const cfg = networkConfig();
  const text = `# RNG Labs / HyperBEAM RNG

HyperBEAM RNG v1 provides replay-stable local randomness, threshold-BLS beacon
rounds, native BLS verification, and deterministic byte derivation for AO.

Canonical domain: hyperbeam/rng/v1
Beacon process: ${cfg.beacon}
Token process: ${cfg.token}
Network: ${cfg.label}

## Product surfaces

- Local: live; deterministic and predictable to the sender.
- Threshold: live; paid request-bound 2-of-3 BLS randomness.
- Beacon: live; Foundation-funded Any-Honest rounds advance continuously.
- Any-Honest: live; time-lock commits, reveals, and cracks are verified by
  ~rng@1.0 on the native testnet.
- Proof Explorer: live; independently verifies retained rounds.

All five surfaces converge on the ~rng@1.0 device namespace. The device owns
cryptographic operations; libraries and processes own delivery, request
binding, balances, and fees.

## What costs credits

- Local deterministic streams: free; no wallet or network.
- Reading rounds: free.
- Verifying a signature: free at the protocol layer.
- Deriving bytes: free at the protocol layer.
- Requesting a new threshold result: 3 TEST-RNG on the current testnet.

Applications should prepay their process balance. End users should not need to
hold or understand RNG credits.

## Agent entry points

- GET /api/status
- POST /api/derive
- POST /mcp (MCP 2026-07-28)

MCP tools: rng_status, rng_verify_round, rng_derive,
rng_integration_guide, rng_request_plan.

## Signature framing

Committee message: hyperbeam/rng/v1|<beacon>|<round>
Round value: SHA-256("hyperbeam/rng/v1/round|" || message || "|" || signature_hex)
Request value: SHA-256("hyperbeam/rng/v1/request|" || round_value || "|" || request_id)

RNG Labs is a product of CipherPlay Inc. and maintains the canonical protocol,
reference network, and provider implementation.
`;
  return new Response(text, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
}
