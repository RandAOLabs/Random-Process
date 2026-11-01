"use client";

import { useState, type CSSProperties } from "react";
import { useLivePoll } from "../hooks/use-live-poll";
import { SiteFooter, SiteHeader } from "./site-header";

type Round = {
  round: number; value: string; opened?: number; finalizedAt?: number;
  commits: Record<string, string>; outputs: Record<string, { via: "reveal" | "crack" }>;
};
type InFlight = { round: number; committed?: unknown; revealed?: unknown };
type Validator = { address: string; suspended?: boolean; exiting?: boolean };
type Beacon = { configured: boolean; proofValid?: boolean; latest?: Round; validators?: Validator[]; open?: InFlight; revealing?: InFlight[] };
type Pulse = { round: number; value: string; commits: number; reveals: number; cracks: number; ms?: number; ok: boolean };
type Cell = "empty" | "locked" | "lit" | "crack";
// slot 1: in progress (bottom), 0: last completed (top), -1: sliding out.
type Track = { round: number; slot: 1 | 0 | -1; commit: Cell[]; reveal: Cell[]; done: boolean; value?: string };

const STAGES = ["COMMIT", "REVEAL", "COMBINE", "VERIFY"];

// Process state serialises sets as either address lists or address-keyed maps.
const members = (set: unknown) => new Set(Array.isArray(set) ? set.map(String) : Object.keys(set ?? {}));

function toPulse(beacon: Beacon): Pulse | null {
  const r = beacon.latest;
  if (!r) return null;
  const outputs = Object.values(r.outputs);
  return {
    round: r.round, value: r.value, commits: Object.keys(r.commits).length,
    reveals: outputs.filter((o) => o.via === "reveal").length, cracks: outputs.filter((o) => o.via === "crack").length,
    ms: r.opened && r.finalizedAt ? r.finalizedAt - r.opened : undefined, ok: Boolean(beacon.proofValid),
  };
}

function toTracks(beacon: Beacon, validators: Validator[]): Track[] {
  const tracks: Track[] = [];
  const latest = beacon.latest;
  if (latest) {
    tracks.push({
      round: latest.round, slot: 0, done: true, value: latest.value,
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
      round: current.round, slot: 1, done: false,
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

function BeaconPipeline({ validators, tracks, ok }: { validators: Validator[]; tracks: Track[]; ok: boolean }) {
  return (
    <div className="pipe">
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

  useLivePoll(async () => {
    try {
      const response = await fetch("/api/anyhonest", { cache: "no-store" });
      if (!response.ok) return;
      const body = await response.json() as Beacon;
      const active = (body.validators ?? []).filter((v) => !v.exiting);
      setValidators(active);
      const next = toTracks(body, active);
      setTracks((prev) => {
        const live = new Set(next.map((t) => t.round));
        // The completed round that was replaced slides out once, then is dropped.
        return [...next, ...prev.filter((t) => t.slot === 0 && !live.has(t.round)).map((t) => ({ ...t, slot: -1 as const }))];
      });
      const pulse = toPulse(body);
      if (pulse) setFeed((prev) => prev[0]?.round === pulse.round ? prev : [pulse, ...prev].slice(0, 3));
    } catch { /* The product explanation remains useful offline. */ }
  }, 150);

  const now = feed[0];
  const live = Boolean(now?.ok);

  return (
    <main className="shell home-page">
      <SiteHeader />

      <section className="home-simple container">
        <div className="home-message">
          <p className="kicker">[ THE BLOCKCHAIN RNG LIBRARY // BUILT ON HYPERBEAM ]</p>
          <h1>Randomness you can prove.</h1>
        </div>

        <a className="rng-visual live-beacon" href="/how" aria-label="Live Any-Honest beacon. Open how it works.">
          <BeaconPipeline validators={validators} tracks={tracks} ok={live} />
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
