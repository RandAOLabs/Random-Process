"use client";

import { useEffect, useMemo, useState } from "react";
import { SiteFooter, SiteHeader } from "./site-header";

type Status = {
  network: string; round: number; threshold: number; committeeSize: number;
  price: number; pending: number; nativeVerification: boolean; groupKey: string;
  message: string; signature: string; value: string; signers: string[];
  verified: boolean; checkedAt: string;
  tokenInfo: { faucetAmount: number; faucetLifetimeCap: number };
};

type WebMcp = { registerTool(tool: { name: string; description: string; inputSchema: object; execute(input: unknown): unknown | Promise<unknown> }, options?: { signal?: AbortSignal }): void | Promise<void> };
declare global { interface Document { readonly modelContext?: WebMcp } }

const ascii = String.raw`┌──────────────────────────────────────────────────────────┐
│ RNG LABS // HYPERBEAM RNG v1                            │
│                                                          │
│  [ REQUEST ]──>[ ROUND LOCK ]──>[ 2/3 BLS ]              │
│                                      │                   │
│                                      v                   │
│                              [ ~rng@1.0 ]──>[ VALUE ]     │
└──────────────────────────────────────────────────────────┘`;

const examples = {
  lua: `local rng = require("rng")\n\nrng.on("Loot-Roll", function(stream, ctx)\n  grantLoot(ctx.player, stream:int(1, 6))\nend)\n\n-- free, local, replay-stable\nrng.request(msg, { on = "Loot-Roll", ctx = { player = msg.From } })\n\n-- threshold-backed\nrng.config({ beacon = BEACON_PROCESS_ID })\nrng.request(msg, { tier = "beacon", on = "Loot-Roll", ctx = { player = msg.From } })`,
  javascript: `const { rng } = connect({ MODE: "mainnet", URL: HYPERBEAM_URL })\n\nconst verified = await rng.verifyRound({\n  publicKey: GROUP_PUBLIC_KEY_HEX,\n  beacon: BEACON_PROCESS_ID,\n  round, signature\n}).then(r => r.json())\n\nconst bytes = await rng.derive({\n  seed: verified.value, counter: 0, bytes: 32\n}).then(r => r.json())`,
  shell: `curl https://randao.net/api/status\n\ncurl -X POST https://randao.net/mcp \\\n+  -H 'content-type: application/json' \\\n+  --data '{"jsonrpc":"2.0","id":1,"method":"tools/call",\n+    "params":{"name":"rng_status","arguments":{}}}'`,
};

const short = (value?: string, size = 12) => value ? `${value.slice(0, size)}…${value.slice(-size)}` : "—";

export function ConsoleDashboard() {
  const [status, setStatus] = useState<Status | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<keyof typeof examples>("lua");

  async function refresh() {
    const response = await fetch("/api/status", { cache: "no-store" });
    const body = await response.json() as Status & { error?: string };
    if (!response.ok) throw new Error(body.error || "status unavailable");
    setStatus(body); setError(null);
    return body;
  }

  useEffect(() => {
    const tick = () => void refresh().catch((problem) => setError(problem instanceof Error ? problem.message : "status unavailable"));
    const initial = window.setTimeout(tick, 0);
    const timer = window.setInterval(tick, 10_000);
    return () => { window.clearTimeout(initial); window.clearInterval(timer); };
  }, []);

  useEffect(() => {
    const registry = document.modelContext;
    if (typeof registry?.registerTool !== "function") return;
    const lifecycle = new AbortController();
    void Promise.resolve(registry.registerTool({
      name: "rng_refresh_status",
      description: "Refresh and return the live HyperBEAM RNG status shown on this page.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => refresh(),
    }, { signal: lifecycle.signal })).catch(() => undefined);
    return () => lifecycle.abort();
  }, []);

  const signerLabel = useMemo(() => status ? `${status.signers.length}/${status.committeeSize}` : "—", [status]);

  return (
    <main className="shell">
      <SiteHeader live={Boolean(status?.verified)} network={status?.network} />

      <section className="hero-cyber container">
        <div className="hero-copy-block">
          <p className="kicker">[ HYPERBEAM_RNG // VERSION_1 ]</p>
          <h1>Randomness for processes that refuse to trust.</h1>
          <p className="lede">Threshold BLS. Replay-stable derivation. Native verification inside HyperBEAM consensus.</p>
          <div className="hero-actions"><a className="button invert" href="/try">$ rng try --interactive</a><a className="text-link" href="#developers">read_the_docs →</a></div>
          <pre className="ascii-frame" aria-label="HyperBEAM RNG protocol flow">{ascii}</pre>
        </div>
        <aside className="terminal live-terminal" aria-live="polite">
          <div className="terminal-bar"><span>rng://status</span><span>● ● ●</span></div>
          <div className="terminal-body">
            <p><span className="prompt">$</span> rng status --verify</p>
            <dl className="terminal-list">
              <div><dt>network</dt><dd>{status?.network ?? "connecting..."}</dd></div>
              <div><dt>round</dt><dd>{status?.round ?? "—"}</dd></div>
              <div><dt>threshold</dt><dd>{status ? `${status.threshold}/${status.committeeSize}` : "—"}</dd></div>
              <div><dt>signers</dt><dd>{signerLabel}</dd></div>
              <div><dt>device</dt><dd>{status?.nativeVerification ? "~rng@1.0" : "pending"}</dd></div>
              <div><dt>proof</dt><dd className={status?.verified ? "pass" : "wait"}>{status?.verified ? "PASS" : "WAIT"}</dd></div>
            </dl>
            <p className="terminal-hash">value::{status?.value ?? error ?? "awaiting beacon"}</p>
            <span className="cursor" aria-hidden="true">█</span>
          </div>
        </aside>
      </section>

      <section className="section container" id="network">
        <div className="section-head"><div><p className="kicker">[ NETWORK_STATE ]</p><h2>Proof, not a status badge.</h2></div><p>The console fetches the beacon, verifies its BLS signature, and recomputes the domain-separated value.</p></div>
        {error && <p className="error" role="alert">ERROR:: {error}</p>}
        <dl className="metrics-grid">
          <div className="metric"><dt>FINALIZED_ROUND</dt><dd>{status?.round ?? "—"}</dd></div>
          <div className="metric"><dt>COMMITTEE</dt><dd>{status ? `${status.threshold}_OF_${status.committeeSize}` : "—"}</dd></div>
          <div className="metric"><dt>REQUEST_PRICE</dt><dd>{status ? `${status.price}_RNG` : "—"}</dd></div>
          <div className="metric"><dt>NATIVE_PROOF</dt><dd>{status?.verified ? "VERIFIED" : "PENDING"}</dd></div>
          <div className="metric wide"><dt>GROUP_PUBLIC_KEY</dt><dd className="hash-text">{status?.groupKey ?? "—"}</dd></div>
          <div className="metric"><dt>PENDING</dt><dd>{status?.pending ?? "—"}</dd></div>
          <div className="metric"><dt>SIGNATURE</dt><dd className="hash-text">{short(status?.signature)}</dd></div>
        </dl>
      </section>

      <section className="section container">
        <div className="protocol-strip" aria-label="Request flow"><span>REQUEST</span><b>→</b><span>LOCK</span><b>→</b><span>PARTIALS</span><b>→</b><span>2/3 BLS</span><b>→</b><span>~rng@1.0</span><b>→</b><span>VALUE</span></div>
      </section>

      <section className="section container try-banner">
        <div><p className="kicker">[ THREE_ENTRY_POINTS ]</p><h2>Don’t read about randomness. Break it yourself.</h2></div>
        <p>Derive locally, verify the live beacon, or request a fresh threshold round.</p>
        <a className="button dark" href="/try">OPEN_TRY_CONSOLE →</a>
      </section>

      <section className="section container token-section">
        <div className="section-head"><div><p className="kicker">[ COST_MODEL ]</p><h2>Apps pay. Players don’t.</h2></div><p>Application processes prepay their beacon balance. End users should never need to understand protocol credits.</p></div>
        <div className="token-grid"><div><span>LOCAL_DERIVE</span><strong>FREE</strong></div><div><span>VERIFY_ROUND</span><strong>FREE</strong></div><div><span>NEW_BEACON_ROUND</span><strong>{status?.price ?? 3} TEST-RNG</strong></div><div><span>FAUCET</span><strong>{status?.tokenInfo.faucetAmount ?? 100} TEST-RNG</strong></div></div>
      </section>

      <section className="section container" id="developers">
        <div className="section-head"><div><p className="kicker">[ DEVELOPER_INTERFACE ]</p><h2>One primitive. Familiar surfaces.</h2></div><p>Start local. Upgrade the value-bearing action to the threshold beacon without rewriting its continuation.</p></div>
        <div className="tabs" role="tablist">{(Object.keys(examples) as Array<keyof typeof examples>).map((name) => <button key={name} role="tab" aria-selected={tab === name} className={tab === name ? "tab active" : "tab"} onClick={() => setTab(name)}>{name.toUpperCase()}</button>)}</div>
        <pre className="code-block"><code>{examples[tab]}</code></pre>
      </section>

      <section className="section container" id="agents">
        <div className="section-head"><div><p className="kicker">[ AGENT_INTERFACE ]</p><h2>MCP-native. No scavenger hunt.</h2></div><p>Agents get bounded, read-only tools for the live protocol and one pure derivation tool.</p></div>
        <div className="agent-grid"><article><code>rng_status</code><p>Read and verify the network.</p></article><article><code>rng_verify_round</code><p>Verify retained history.</p></article><article><code>rng_derive</code><p>Derive canonical bytes.</p></article><article><code>rng_integration_guide</code><p>Get current integration code.</p></article><article><code>rng_request_plan</code><p>Understand wallet and credit needs.</p></article><article><code>GET /llms.txt</code><p>Read the protocol summary.</p></article></div>
      </section>

      <SiteFooter />
    </main>
  );
}
