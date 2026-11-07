import { extendedNetworkConfig } from "../../lib/rng";

export const dynamic = "force-dynamic";

export async function GET() {
  const cfg = extendedNetworkConfig();
  const text = `# RNG Labs / HyperBEAM RNG

HyperBEAM RNG v1 provides replay-stable local randomness, on-demand threshold-BLS (fast)
rounds, native BLS verification, and deterministic byte derivation for AO.

Canonical domain: hyperbeam/rng/v1
Beacon process: ${cfg.beacon}
Any-Honest process: ${cfg.anyHonest}
Governance process: ${cfg.dao}
Token process: ${cfg.token}
Network: ${cfg.label}

## Product surfaces

- Local: live; deterministic and predictable to the sender.
- Fast: live; paid, on-demand 2-of-3 threshold BLS (not a heartbeat: a round opens only for paid requests). Safe unless 2 of 3 operators collude.
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
- Requesting a new fast result: 3 RNG on the current testnet.
- Requesting a one-shot Any-Honest result: 4 TEST-RNG.
- Secure process subscription: 1 TEST-RNG for 1,000 authenticated pushes.

Public reads are free but inherit the selected gateway view. The strongest
delivery path is a prepaid AO process subscription bound before the reveal
phase; the beacon then pushes the authenticated result to that process.

Applications should prepay their process balance. End users should not need to
hold or understand RNG credits.

## Agent entry points

- GET /api/status
- POST /api/derive
- POST /mcp (MCP 2026-07-28)

MCP tools: rng_status, rng_verify_round, rng_anyhonest_status,
rng_governance_status, rng_derive, rng_integration_guide, rng_request_plan.

Governance is advisory. Token-weighted votes establish the DAO's decision;
administrators manually execute and record passed proposals after technical
review. The DAO cannot upgrade contracts or move funds automatically.

## Signature framing

Committee message: hyperbeam/rng/v1|<beacon>|<round>
Round value: SHA-256("hyperbeam/rng/v1/round|" || message || "|" || signature_hex)
Request value: SHA-256("hyperbeam/rng/v1/request|" || round_value || "|" || request_id)

RNG Labs is a product of CipherPlay Inc. and maintains the canonical protocol,
reference network, and provider implementation.
`;
  return new Response(text, { headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
}
