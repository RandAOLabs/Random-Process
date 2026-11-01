# RNG Labs Console

The CipherPlay-owned console for HyperBEAM RNG. It provides:

- live beacon and committee status;
- independent BLS signature and round-value verification;
- a five-surface try console for local, threshold, beacon, Any-Honest, and
  proof exploration, with live and restoring states shown explicitly;
- a guided Wander faucet, funding, request, and proof flow;
- current Lua, JavaScript and HTTP integration documentation;
- a Site-hosted MCP endpoint at `POST /mcp`;
- an agent-readable protocol summary at `GET /llms.txt`; and
- in-page WebMCP tools for status refresh and derivation.

## Runtime configuration

The deployment supplies these environment variables:

- `RNG_NODE_URL`
- `RNG_BEACON_ID`
- `RNG_TOKEN_ID`
- `RNG_NETWORK_LABEL`

Keeping network identity out of the bundle allows a beacon, token, node or
domain cutover without changing the UI source.

## Local development

```bash
npm run dev
```

Set the four runtime variables in the shell that launches the preview. Build
and deployment follow the Sites workflow documented by the project tooling.

## MCP tools

- `rng_status`
- `rng_verify_round`
- `rng_derive`
- `rng_integration_guide`
- `rng_request_plan`

The initial MCP surface is read-only except for pure deterministic derivation.
It never receives or stores wallet keys.

The visual system is deliberately monochrome and terminal-led. The persistent
header rail keeps WHY, HOW, and TRY available at every viewport width. The
five-product console defaults to the public beacon and changes its explanation
and controls with the selected surface.
