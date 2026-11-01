"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { SiteFooter, SiteHeader } from "./site-header";

type Status = {
  network: string; round: number; threshold: number; committeeSize: number;
  nativeVerification: boolean; verified: boolean; value: string;
};

export function ConsoleDashboard() {
  const [status, setStatus] = useState<Status | null>(null);

  useEffect(() => {
    const tick = async () => {
      try {
        const response = await fetch("/api/status", { cache: "no-store" });
        if (response.ok) setStatus(await response.json() as Status);
      } catch { /* The product explanation remains useful offline. */ }
    };
    const initial = window.setTimeout(() => void tick(), 0);
    const timer = window.setInterval(() => void tick(), 10_000);
    return () => { window.clearTimeout(initial); window.clearInterval(timer); };
  }, []);

  return (
    <main className="shell">
      <SiteHeader live={Boolean(status?.verified)} network={status?.network} />

      <section className="home-simple container">
        <div className="home-message">
          <p className="kicker">[ THE BLOCKCHAIN RNG LIBRARY // BUILT ON HYPERBEAM ]</p>
          <h1>Randomness you can prove.</h1>
          <div className="hero-actions"><a className="button invert" href="/try">ENTER_THE_CONSOLE →</a><a className="text-link" href="/how">see_how_it_works</a></div>
          <div className="hero-command"><span>$</span> rng request <b>--verify=native</b><i className="cursor">█</i></div>
        </div>

        <aside className="rng-visual" aria-label="HyperBEAM native randomness proof">
          <div className="rng-orbit">
            <span className="orbit ring-one" />
            <span className="orbit ring-two" />
            <span className="orbit ring-three" />
            <span className="orbit-node node-one" />
            <span className="orbit-node node-two" />
            <span className="orbit-node node-three" />
            <Image src="/rng.png" alt="RNG" width={260} height={260} className="home-rng-mark" priority unoptimized />
            <code className="visual-label label-one">THRESHOLD_BLS</code>
            <code className="visual-label label-two">REPLAY_SAFE</code>
            <code className="visual-label label-three">~rng@1.0</code>
          </div>
          <div className="home-status"><span className={status?.verified ? "signal on" : "signal"} /><strong>{status?.verified ? "NATIVE_PROOF::PASS" : "CONNECTING"}</strong><small>{status ? `ROUND_${status.round} // ${status.threshold}_OF_${status.committeeSize} // ${status.nativeVerification ? "HYPERBEAM" : "FALLBACK"}` : "READING_NATIVE_TESTNET"}</small></div>
        </aside>
      </section>

      <section className="home-promises container">
        <article><span>01</span><h2>Deterministic by default.</h2><p>Every node and replay reaches the same result.</p></article>
        <article><span>02</span><h2>Verifiable when it matters.</h2><p>Threshold BLS rounds produce a proof anyone can check.</p></article>
        <article><span>03</span><h2>One library.</h2><p>Move from local draws to beacon-backed results with one option.</p></article>
      </section>

      <section className="route-section container">
        <p className="kicker">[ START_HERE ]</p>
        <div className="route-grid">
          <a href="/why"><span>01</span><h2>WHY</h2><p>Why ordinary randomness fails on deterministic blockchains.</p><b>READ_WHY →</b></a>
          <a href="/how"><span>02</span><h2>HOW</h2><p>How local streams, threshold rounds, verification and pricing work.</p><b>SEE_THE_PROTOCOL →</b></a>
          <a href="/try"><span>03</span><h2>TRY</h2><p>Derive locally, verify a round, or request fresh randomness.</p><b>OPEN_CONSOLE →</b></a>
        </div>
      </section>

      <SiteFooter />
    </main>
  );
}
