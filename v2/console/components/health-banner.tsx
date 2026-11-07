"use client";

import { useRef, useState } from "react";
import { useLivePoll } from "../hooks/use-live-poll";

type Validator = { ready?: boolean; suspended?: boolean; exiting?: boolean; overdue?: boolean };
export type BeaconHealthInput = {
  configured?: boolean;
  round?: number;
  mode?: string;
  validators?: Validator[];
  params?: { minCommits?: number; heartbeat?: number };
  health?: { status?: "ok" | "degraded" | "halted"; active?: number; eligible?: number; minCommits?: number };
};
export type HealthView = { status: "ok" | "degraded" | "halted"; message: string };

// No new round for this long with the heartbeat on counts as a stall. Rounds
// normally finalize about twice a second.
const STALL_MS = 90_000;

// Prefer the beacon's own `health` (v3). Older beacons don't publish it, so the
// same rule is derived from the validator list: halted when fewer validators
// are eligible than a round needs, degraded when most are suspended.
export function beaconHealth(body: BeaconHealthInput, stalledForMs = 0): HealthView {
  const minCommits = body.health?.minCommits ?? body.params?.minCommits ?? 2;
  const all = body.validators ?? [];
  const eligible = body.health?.eligible
    ?? all.filter((v) => v.ready !== false && !v.suspended && !v.exiting && !v.overdue).length;
  const status = body.health?.status
    ?? (all.length > 0 && eligible < minCommits ? "halted" : all.length > 0 && eligible * 2 < all.length ? "degraded" : "ok");
  if (status === "halted") {
    return { status, message: `Rounds are halted: ${eligible} validator${eligible === 1 ? " is" : "s are"} eligible and a round needs ${minCommits}. Pending requests are refunded after the abandon window.` };
  }
  if (status === "degraded") {
    return { status, message: `The beacon is degraded: only ${eligible} of ${all.length} validators are eligible right now.` };
  }
  const heartbeat = Number(body.params?.heartbeat ?? 1) === 1 && body.mode !== "request-driven";
  if (heartbeat && stalledForMs > STALL_MS) {
    return { status: "degraded", message: `No new round for ${Math.round(stalledForMs / 1000)} s. The beacon may be stalled.` };
  }
  return { status: "ok", message: "" };
}

export function HealthBanner() {
  const [view, setView] = useState<HealthView>({ status: "ok", message: "" });
  // Local clock only: when this page last saw the round number change.
  const last = useRef<{ round: number; at: number } | null>(null);

  useLivePoll(async () => {
    const response = await fetch("/api/anyhonest", { cache: "no-store" });
    if (!response.ok) return;
    const body = await response.json() as BeaconHealthInput;
    if (!body.configured) return;
    const now = Date.now();
    const round = body.round ?? 0;
    if (!last.current || round !== last.current.round) last.current = { round, at: now };
    setView(beaconHealth(body, now - last.current.at));
  }, 15_000);

  if (view.status === "ok") return null;
  return (
    <div role="status" className="fixed inset-x-0 bottom-0 z-30 border-t border-[var(--line)] bg-[#0c0c0c]/95 px-4 py-3 text-[12px] leading-relaxed text-[var(--white)] backdrop-blur">
      <div className="mx-auto flex max-w-[1380px] flex-wrap items-center gap-x-3 gap-y-1">
        <span className={view.status === "halted" ? "font-bold text-[#ff8a7a]" : "font-bold text-[#f0c674]"}>
          {view.status === "halted" ? "Beacon halted" : "Beacon degraded"}
        </span>
        <span className="text-[var(--gray)]">{view.message}</span>
        <a href="/validators" className="text-[var(--white)] underline underline-offset-2">Run a validator</a>
      </div>
    </div>
  );
}
