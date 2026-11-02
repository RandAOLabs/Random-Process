"use client";

import { useRef, useState, type CSSProperties } from "react";
import { useLivePoll } from "../hooks/use-live-poll";
import { SiteFooter, SiteHeader } from "./site-header";

type Round = {
  round: number; value: string; opened?: number; finalizedAt?: number;
  commits: Record<string, string>; outputs: Record<string, { via: "reveal" | "crack" }>;
};
type InFlight = { round: number; committed?: unknown; revealed?: unknown };
type Validator = { address: string; suspended?: boolean; exiting?: boolean };
type Recent = { round: number; value: string; opened?: number; finalizedAt?: number };
type Beacon = { configured: boolean; round?: number; proofValid?: boolean; latest?: Round; recent?: Recent[]; validators?: Validator[]; open?: InFlight; revealing?: InFlight[] };
type Pulse = { round: number; value: string; ms?: number };
type Cell = "empty" | "locked" | "lit" | "crack";
// slot 0: in progress (top), 1: last completed (below), 2: sliding out.
type Track = { round: number; slot: 0 | 1 | 2; commit: Cell[]; reveal: Cell[]; done: boolean; value?: string };

const STAGES = ["COMMIT", "REVEAL", "COMBINE", "VERIFY"];

// Process state serialises sets as either address lists or address-keyed maps.
const members = (set: unknown) => new Set(Array.isArray(set) ? set.map(String) : Object.keys(set ?? {}));

const toPulse = (r: Recent): Pulse => ({
  round: r.round, value: r.value, ms: r.opened && r.finalizedAt ? r.finalizedAt - r.opened : undefined,
});

function toTracks(beacon: Beacon, validators: Validator[]): Track[] {
  const tracks: Track[] = [];
  const latest = beacon.latest;
  if (latest) {
    tracks.push({
      round: latest.round, slot: 1, done: true, value: latest.value,
      commit: validators.map((v) => latest.commits[v.address] ? "locked" : "empty"),
      reveal: validators.map((v) => latest.outputs[v.address]?.via === "crack" ? "crack" : latest.outputs[v.address] ? "lit" : "empty"),
    });
  }
  // The round furthest along after the latest one is the one shown in progress.
  const current = [...(beacon.revealing ?? []), ...(beacon.open ? [beacon.open] : [])]
    .filter((r) => !latest || r.round > latest.round).sort((x, y) => x.round - y.round)[0];
  if (current) {
    const committed = members(current.committed), revealed = members(current.revealed);
    tracks.push({
      round: current.round, slot: 0, done: false,
      commit: validators.map((v) => committed.has(v.address) ? "locked" : "empty"),
      reveal: validators.map((v) => revealed.has(v.address) ? "lit" : "empty"),
    });
  }
  return tracks;
}

function RoundTrack({ track, ok }: { track: Track; ok: boolean }) {
  const committed = track.commit.some((c) => c !== "empty");
  const revealed = track.done || track.reveal.every((c) => c !== "empty");
  const state = [
    committed ? "done" : "active",
    revealed ? "done" : committed ? "active" : "",
    track.done ? "done" : "",
    track.done ? "done" : "",
  ];
  return (
    <div className={`track slot-${track.slot}`} style={{ "--slot": track.slot } as CSSProperties}>
      <div className="track-tag"><b>#{track.round}</b><span>{track.done ? "DONE" : "LIVE"}</span></div>
      <div className={`stage-box ${state[0]}`}>{track.commit.map((c, i) => <span key={i} className={`cell ${c}`} />)}</div>
      <div className={`stage-box ${state[1]}`}>{track.reveal.map((c, i) => <span key={i} className={`cell ${c}`} />)}</div>
      <div className={`stage-box ${state[2]}`}>{track.done ? <span className="merge" /> : track.reveal.map((_, i) => <span key={i} className="cell empty" />)}</div>
      <div className={`stage-box ${state[3]}`}>{track.done ? <span className="verdict"><b>{ok ? "PASS" : "WAIT"}</b><code>{track.value?.slice(0, 10)}</code></span> : <span className="verdict pending">—</span>}</div>
    </div>
  );
}

function BeaconPipeline({ validators, tracks, ok, total }: { validators: Validator[]; tracks: Track[]; ok: boolean; total?: number }) {
  return (
    <div className="pipe">
      <div className="pipe-total"><span>TOTAL_ROUNDS</span><b>{total?.toLocaleString("en-US") ?? "—"}</b></div>
      <div className="pipe-head">
        <div><span>VALIDATORS</span><b>{validators.length || "—"}</b></div>
        {STAGES.map((stage) => <div key={stage}><span>{stage}</span></div>)}
      </div>
      <div className="tracks">{tracks.map((t) => <RoundTrack key={t.round} track={t} ok={ok} />)}</div>
    </div>
  );
}

export function ConsoleDashboard() {
  const [feed, setFeed] = useState<Pulse[]>([]);
  const [validators, setValidators] = useState<Validator[]>([]);
  const [tracks, setTracks] = useState<Track[]>([]);

  const [total, setTotal] = useState<number>();
  const [live, setLive] = useState(false);
  const seen = useRef(0);

  // Reads take longer than a round, so three staggered lanes keep a fresh
  // sample arriving every ~half second; stale responses are dropped.
  useLivePoll(async () => {
    try {
      const response = await fetch("/api/anyhonest", { cache: "no-store" });
      if (!response.ok) return;
      const body = await response.json() as Beacon;
      const round = body.round ?? 0;
      if (round < seen.current) return;
      seen.current = round;
      const active = (body.validators ?? []).filter((v) => !v.exiting);
      setValidators(active);
      setTotal(body.latest?.round);
      setLive(Boolean(body.proofValid));
      const next = toTracks(body, active);
      setTracks((prev) => {
        const live = new Set(next.map((t) => t.round));
        // The completed round that was replaced slides down once, then is dropped.
        return [...next, ...prev.filter((t) => t.slot === 1 && !live.has(t.round)).map((t) => ({ ...t, slot: 2 as const }))];
      });
      // Backfill rounds that finalized between samples.
      const recent = body.recent ?? (body.latest ? [body.latest] : []);
      setFeed((prev) => {
        const known = new Set(prev.map((p) => p.round));
        const added = recent.filter((r) => !known.has(r.round)).map(toPulse);
        return added.length ? [...added, ...prev].sort((x, y) => y.round - x.round).slice(0, 3) : prev;
      });
    } catch { /* The product explanation remains useful offline. */ }
  }, 150, 3, 450);

  const now = feed[0];

  return (
    <main className="shell home-page">
      <SiteHeader />

      <section className="home-simple container">
        <div className="home-message">
          <p className="kicker">[ THE BLOCKCHAIN RNG LIBRARY // BUILT ON HYPERBEAM ]</p>
          <h1>Randomness you can prove.</h1>
        </div>

        <a className="rng-visual live-beacon" href="/how" aria-label="Live Any-Honest beacon. Open how it works.">
          <BeaconPipeline validators={validators} tracks={tracks} ok={live} total={total} />
          <ul className="beacon-feed">
            {feed.map((p, i) => <li key={p.round} className={i === 0 ? "fresh" : undefined}><span>#{p.round}</span><code>{p.value.slice(0, 24)}</code><b>{p.ms ? `${p.ms}ms` : ""}</b></li>)}
          </ul>
          <div className="home-status"><span className={live ? "signal on" : "signal"} /><strong>{live ? "ANY_HONEST::PASS" : "CONNECTING"}</strong><small>{now ? `ROUND_${now.round} // ${validators.length}_VALIDATORS // 1_PER_SEC // HOW_IT_WORKS →` : "READING_NATIVE_TESTNET"}</small></div>
        </a>
      </section>

      <SiteFooter />
    </main>
  );
}
