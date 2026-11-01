"use client";

import { useEffect, useState } from "react";
import { SiteFooter, SiteHeader } from "./site-header";

type Status = {
  network: string; round: number; threshold: number; committeeSize: number;
  price: number; nativeVerification: boolean; verified: boolean; value: string;
};

const surfaces = [
  ["01", "LOCAL", "LIVE", "derive", "free"],
  ["02", "THRESHOLD", "LIVE", "verify-bls", "3 TEST-RNG"],
  ["03", "BEACON", "NOT DEPLOYED", "beacon", "read free"],
  ["04", "ANY-HONEST", "RESTORING", "verify-reveal + verify-crack", "target 4 TEST-RNG"],
  ["05", "PROOF", "LIVE", "verify", "free"],
];

export function HowProtocol() {
  const [status, setStatus] = useState<Status | null>(null);

  useEffect(() => {
    const tick = async () => {
      try {
        const response = await fetch("/api/status", { cache: "no-store" });
        if (response.ok) setStatus(await response.json() as Status);
      } catch { /* The device map remains useful offline. */ }
    };
    const initial = window.setTimeout(() => void tick(), 0);
    const timer = window.setInterval(() => void tick(), 10_000);
    return () => { window.clearTimeout(initial); window.clearInterval(timer); };
  }, []);

  return (
    <main className="shell compact-page">
      <SiteHeader live={Boolean(status?.verified)} network={status?.network} active="how" />
      <section className="page-titlebar container"><div><p className="kicker">[ 02 // HOW ]</p><h1>Five surfaces. One device.</h1></div><p>The library and beacon processes handle delivery. <code>~rng@1.0</code> handles deterministic cryptography.</p></section>
      <section className="how-board container">
        <div className="how-surface-table"><div className="table-head"><span>#</span><span>SURFACE</span><span>STATUS</span><span>DEVICE OP</span><span>COST</span></div>{surfaces.map(([index, name, state, operation, cost]) => <div className="table-row" key={name}><span>{index}</span><b>{name}</b><span>{state}</span><code>/{operation}</code><span>{name === "THRESHOLD" && status ? `${status.price} TEST-RNG` : cost}</span></div>)}</div>
        <div className="how-lower"><div className="flow-panel"><p className="board-label">THRESHOLD_FLOW</p><div className="flow-line"><span>REQUEST_LOCK</span><i>→</i><span>2/3 BLS</span><i>→</i><span>~rng@1.0</span><i>→</i><span>VALUE</span></div><p>Any-Honest replaces the committee signature step with time-lock commit, reveal, crack, and combine.</p></div><dl className="compact-live" id="live"><div><dt>NETWORK</dt><dd>{status?.network ?? "—"}</dd></div><div><dt>ROUND</dt><dd>{status?.round ?? "—"}</dd></div><div><dt>THRESHOLD</dt><dd>{status ? `${status.threshold}/${status.committeeSize}` : "—"}</dd></div><div><dt>DEVICE</dt><dd>{status?.nativeVerification ? "~rng@1.0" : "—"}</dd></div><div><dt>PROOF</dt><dd className={status?.verified ? "pass" : "wait"}>{status?.verified ? "PASS" : "WAIT"}</dd></div><div className="value"><dt>VALUE</dt><dd>{status?.value ?? "—"}</dd></div></dl></div>
      </section>
      <SiteFooter />
    </main>
  );
}
