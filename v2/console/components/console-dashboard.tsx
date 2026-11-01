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
    <main className="shell home-page">
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

      <SiteFooter />
    </main>
  );
}
