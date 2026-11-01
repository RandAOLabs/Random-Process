"use client";

import { useEffect, useState } from "react";
import { SiteFooter, SiteHeader } from "./site-header";

type Status = {
  network: string;
  round: number;
  threshold: number;
  committeeSize: number;
  price: number;
  nativeVerification: boolean;
  verified: boolean;
  value: string;
};

const flow = String.raw`APP_REQUEST
    │
    ▼
LOCK_REQUEST_SET ──▶ COMMITTEE_SIGNS ──▶ 2_OF_3_THRESHOLD
                                              │
                                              ▼
                                    ~rng@1.0 VERIFIES
                                              │
                                              ▼
                                      REPLAY-SAFE VALUE`;

export function HowProtocol() {
  const [status, setStatus] = useState<Status | null>(null);

  useEffect(() => {
    const tick = async () => {
      try {
        const response = await fetch("/api/status", { cache: "no-store" });
        if (response.ok) setStatus(await response.json() as Status);
      } catch { /* Protocol documentation remains readable while offline. */ }
    };
    const initial = window.setTimeout(() => void tick(), 0);
    const timer = window.setInterval(() => void tick(), 10_000);
    return () => { window.clearTimeout(initial); window.clearInterval(timer); };
  }, []);

  return (
    <main className="shell">
      <SiteHeader live={Boolean(status?.verified)} network={status?.network} />

      <section className="content-hero container">
        <p className="kicker">[ 02 // HOW ]</p>
        <h1>One library. Two sources. One verifier.</h1>
        <p className="lede">Start with a deterministic local stream. Select the threshold beacon when an outcome must remain unpredictable until everyone is committed.</p>
      </section>

      <section className="section container">
        <div className="section-head"><div><p className="kicker">[ CHOOSE_THE_SOURCE ]</p><h2>Use only the trust you need.</h2></div><p>The same RNG library exposes both paths, so applications do not need two incompatible randomness systems.</p></div>
        <div className="source-grid">
          <article><span>LOCAL_STREAM</span><h3>Deterministic and free.</h3><p>A seed, byte count and counter are length-framed and expanded with SHA-256. Every process replay gets identical bytes.</p><dl><div><dt>USE_FOR</dt><dd>simulation, shuffling without adversarial value, reproducible tests</dd></div><div><dt>WALLET</dt><dd>none</dd></div><div><dt>PRICE</dt><dd>free</dd></div></dl></article>
          <article><span>THRESHOLD_BEACON</span><h3>Unpredictable before commitment.</h3><p>Requests are locked into a round before signature shares appear. Any valid threshold produces the same unique BLS signature.</p><dl><div><dt>USE_FOR</dt><dd>games, lotteries, rewards, markets and contested ordering</dd></div><div><dt>WALLET</dt><dd>application funds beacon</dd></div><div><dt>PRICE</dt><dd>{status ? `${status.price} TEST-RNG` : "3 TEST-RNG"}</dd></div></dl></article>
        </div>
      </section>

      <section className="section container protocol-explanation">
        <div><p className="kicker">[ REQUEST_LIFECYCLE ]</p><h2>Commit first. Reveal second.</h2><p className="muted">Each request receives a unique, domain-separated result from the finalized round. The round signature and value remain independently verifiable.</p></div>
        <pre aria-label="Threshold randomness request flow">{flow}</pre>
      </section>

      <section className="section container cost-section">
        <div><p className="kicker">[ WHO_PAYS ]</p><h2>Users do not need RNG tokens.</h2></div>
        <div className="cost-ledger">
          <div><span>FREE</span><p>Local derivation, reading rounds, verifying signatures and deriving bytes.</p></div>
          <div><span>{status ? status.price : 3} TEST-RNG</span><p>A new threshold-beacon request on the testnet. Test credits have no monetary value.</p></div>
          <div><span>RECOMMENDED</span><p>The AO application prepays its beacon balance. End users simply use the application.</p></div>
        </div>
      </section>

      <section className="section container" id="live">
        <div className="section-head"><div><p className="kicker">[ LIVE_NATIVE_PROOF ]</p><h2>The verifier is part of HyperBEAM.</h2></div><p>The preloaded <code>~rng@1.0</code> device verifies BLS12-381 signatures and derives replay-safe bytes inside the compute environment.</p></div>
        <dl className="live-ledger">
          <div><dt>NETWORK</dt><dd>{status?.network ?? "CONNECTING"}</dd></div>
          <div><dt>LATEST_ROUND</dt><dd>{status?.round ?? "—"}</dd></div>
          <div><dt>THRESHOLD</dt><dd>{status ? `${status.threshold}_OF_${status.committeeSize}` : "—"}</dd></div>
          <div><dt>DEVICE</dt><dd>{status?.nativeVerification ? "~rng@1.0" : "—"}</dd></div>
          <div className="wide"><dt>INDEPENDENT_CHECK</dt><dd className={status?.verified ? "pass" : "wait"}>{status?.verified ? "VERIFIED" : "WAITING"}</dd></div>
          <div className="wide"><dt>ROUND_VALUE</dt><dd className="hash-text">{status?.value ?? "reading native testnet"}</dd></div>
        </dl>
      </section>

      <section className="section container developer-entry">
        <div><p className="kicker">[ BUILD_WITH_IT ]</p><h2>Humans and agents get the same protocol.</h2><p className="muted">Lua applications import the RNG library. Agents can discover the read-only MCP tools and integration guides without receiving wallet keys.</p></div>
        <div className="endpoint-list"><a href="/llms.txt"><code>GET /llms.txt</code><span>agent-readable protocol map</span></a><a href="/mcp"><code>POST /mcp</code><span>status, verification, derivation and guides</span></a><a href="https://github.com/RandAOLabs/Random-Process/tree/v2/v2" target="_blank" rel="noreferrer"><code>LIB / SPEC</code><span>canonical implementation and protocol</span></a></div>
      </section>

      <section className="next-page container"><span>NEXT::</span><a href="/try">TRY_THE_LIVE_PRIMITIVE →</a></section>
      <SiteFooter />
    </main>
  );
}
