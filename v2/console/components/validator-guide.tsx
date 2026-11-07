"use client";

import { useState, type CSSProperties, type ReactNode } from "react";
import { useLivePoll } from "../hooks/use-live-poll";
import { beaconHealth, type BeaconHealthInput } from "./health-banner";

type Validator = { address: string; ready?: boolean; suspended?: boolean; exiting?: boolean; overdue?: boolean; bond?: number; faults?: number };
type Params = {
  stake?: number; slash?: number; maxActive?: number; maxValidators?: number; minCommits?: number;
  commitWindowMs?: number; targetIntervalMs?: number; rejoinBaseMs?: number; rejoinCapMs?: number;
  roundPrice?: number; requestPrice?: number; heartbeat?: number;
};
type Beacon = BeaconHealthInput & {
  configured?: boolean; process?: string; validators?: Validator[]; params?: Params;
  priceSchedule?: { round?: number; request?: number; crackBounty?: number };
};

// Defaults from docs/PERMISSIONLESS.md, used until the live beacon publishes its own.
const DEFAULTS = { stake: 25_000, slash: 1_000, maxActive: 64, maxValidators: 256, roundPrice: 1, requestPrice: 4, targetIntervalMs: 500, commitWindowMs: 5_000, rejoinBaseMs: 60_000, rejoinCapMs: 3_600_000 };

// Heartbeat pay per validator: every round pays `roundPrice`, split across the
// active set. Requests add (requestPrice - 1) / active each (1 goes to the treasury).
export function estimateEarnings(roundPrice: number, roundsPerSecond: number, active: number) {
  const n = Math.max(1, active);
  const perSecond = (roundPrice * roundsPerSecond) / n;
  return { perSecond, perDay: perSecond * 86_400, perRound: roundPrice / n };
}

const fmt = (x: number, digits = 0) => x.toLocaleString("en-US", { maximumFractionDigits: digits });
const duration = (ms: number) => ms >= 3_600_000 ? `${fmt(ms / 3_600_000, 1)} h` : ms >= 60_000 ? `${fmt(ms / 60_000, 1)} min` : `${fmt(ms / 1000, 1)} s`;

// Global h1/h2 rules are display-sized and uppercase; this page uses plain headings.
const h1: CSSProperties = { fontFamily: "var(--display)", fontSize: 30, lineHeight: 1.2, letterSpacing: "-.01em", textTransform: "none" };
const h2: CSSProperties = { fontFamily: "var(--display)", fontSize: 20, lineHeight: 1.3, letterSpacing: 0, textTransform: "none", marginBottom: 12 };

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="border-t border-[var(--line)] py-8">
      <h2 style={h2}>{title}</h2>
      <div className="max-w-[860px] space-y-3 text-[14px] leading-relaxed text-[var(--gray)]">{children}</div>
    </section>
  );
}

function Command({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => {
    try { await navigator.clipboard.writeText(text); setCopied(true); window.setTimeout(() => setCopied(false), 1500); } catch { /* clipboard unavailable */ }
  };
  return (
    <div className="flex items-start gap-2 border border-[var(--line)] bg-black/60 p-3">
      <pre className="m-0 min-w-0 flex-1 overflow-x-auto whitespace-pre text-[12px] text-[#d9d9d4]">{text}</pre>
      <button type="button" onClick={copy} className="shrink-0 border border-[var(--line)] px-2 py-1 text-[11px] text-[var(--gray)] hover:border-[var(--white)] hover:text-[var(--white)]">
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="border border-[var(--line)] bg-[#0c0c0c] p-3">
      <dt className="text-[11px] text-[var(--dim)]">{label}</dt>
      <dd className="m-0 mt-1 text-[15px] text-[var(--white)] tabular-nums">{value}</dd>
    </div>
  );
}

export function ValidatorGuide() {
  const [beacon, setBeacon] = useState<Beacon>();
  const [error, setError] = useState("");

  useLivePoll(async () => {
    try {
      const response = await fetch("/api/anyhonest", { cache: "no-store" });
      const body = await response.json() as Beacon & { error?: string };
      if (!response.ok) { setError(body.error ?? `HTTP ${response.status}`); return; }
      setBeacon(body); setError("");
    } catch (e) { setError(e instanceof Error ? e.message : "Beacon unavailable"); }
  }, 10_000);

  const p = { ...DEFAULTS, ...(beacon?.params ?? {}) };
  const roundPrice = beacon?.priceSchedule?.round ?? p.roundPrice;
  const requestPrice = beacon?.priceSchedule?.request ?? p.requestPrice;
  const validators = beacon?.validators ?? [];
  const active = validators.filter((v) => v.ready !== false && !v.suspended && !v.exiting && !v.overdue).length;
  const health = beacon?.configured ? beaconHealth(beacon) : undefined;
  const rate = 1000 / p.targetIntervalMs;
  const now = estimateEarnings(roundPrice, rate, active + 1);
  const full = estimateEarnings(roundPrice, rate, p.maxActive);
  const stakeUnits = `${p.stake}000000`;

  return (
    <div className="container pb-24">
      <section className="py-10">
        <h1 style={h1}>Become a validator</h1>
        <div className="mt-4 max-w-[760px] space-y-3 text-[15px] leading-relaxed text-[var(--gray)]">
          <p className="m-0">Anyone with a wallet and {fmt(p.stake)} RNG can validate the Any-Honest beacon. There is no allowlist: you bond RNG, your validator marks itself ready, and it takes part in rounds while it ranks in the active set.</p>
          <p className="m-0">Validators commit a time-lock puzzle each round and reveal it after the commit window closes. One honest validator is enough to keep a round unpredictable. You are paid in RNG for every round you complete and lose part of your bond for every duty you miss.</p>
        </div>
      </section>

      <Section title="Live beacon">
        {error && <p className="m-0 text-[#ff8a7a]">Could not read the beacon: {error}</p>}
        {beacon && !beacon.configured && <p className="m-0">The beacon is not deployed on this network yet.</p>}
        <dl className="m-0 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
          <Stat label="Registered" value={beacon?.configured ? fmt(validators.length) : "-"} />
          <Stat label="Active / cap" value={beacon?.configured ? `${fmt(active)} / ${fmt(p.maxActive)}` : "-"} />
          <Stat label="Health" value={health ? health.status : "-"} />
          <Stat label="Bond" value={`${fmt(p.stake)} RNG`} />
          <Stat label="Slash per miss" value={`${fmt(p.slash)} RNG`} />
          <Stat label="Round price" value={`${fmt(roundPrice)} RNG`} />
        </dl>
        {health && health.status !== "ok" && <p className="m-0">{health.message}</p>}
      </Section>

      <Section title="Who can validate">
        <ul className="m-0 list-disc space-y-1 pl-5">
          <li>Anyone holding at least {fmt(p.stake)} RNG for the bond.</li>
          <li>A machine with Node 22 and a durable disk for the wallet and round secrets. Losing secrets costs a slash per open round.</li>
          <li>A round trip to the scheduler under {fmt(p.commitWindowMs / 2)} ms (half the commit window). The client refuses to mark itself ready until it measures this.</li>
        </ul>
        <p className="m-0">The registry holds up to {fmt(p.maxValidators)} validators. Each round uses at most {fmt(p.maxActive)}, ranked by bond (counted up to {fmt(4 * p.stake)} RNG), then by how long they have been registered.</p>
      </Section>

      <Section title="Two ways to run">
        <div className="grid gap-3 md:grid-cols-2">
          <div className="border border-[var(--line)] p-4">
            <p className="m-0 font-bold text-[var(--white)]">JS validator (recommended)</p>
            <p className="m-0 mt-2">One Node script, <code>v2/provider/anyhonest-validator.mjs</code>. Commits are computed locally; reveals are verified by the beacon&apos;s node, so you do not need HyperBEAM.</p>
          </div>
          <div className="border border-[var(--line)] p-4">
            <p className="m-0 font-bold text-[var(--white)]">HyperBEAM node</p>
            <p className="m-0 mt-2">Build the HyperBEAM fork with the <code>rng-validator@1.0</code> device (started by the <code>on.start</code> hook) and <code>rng@1.0</code> (blst NIF). Same bond and rules; more work to set up.</p>
          </div>
        </div>
      </Section>

      <Section title="Steps">
        <p className="m-0">The config file is JSON: <code>{"{ beacon, hbNode, dataDir }"}</code>. Exact flags may change; see the repo README.</p>
        <ol className="m-0 list-decimal space-y-4 pl-5">
          <li><p className="m-0 mb-2">Create the validator wallet. It prints your address.</p><Command text="node v2/provider/anyhonest-validator.mjs init validator.json" /></li>
          <li><p className="m-0">Buy at least {fmt(p.stake)} RNG and send it to that address. RNG will trade on the Paralith orderbook (RNG/GOLD), <span className="text-[var(--white)]">coming soon</span>. RNG has a fixed supply and no faucet.</p></li>
          <li><p className="m-0 mb-2">Bond: transfer the stake to the beacon with the <code>X-Bond</code> tag. A first bond below {fmt(p.stake)} RNG is refunded. The validator&apos;s bond command sends this for you (see repo README for flags).</p><Command text={`Transfer { Recipient = <beacon>, Quantity = ${stakeUnits}, X-Bond = "true" }`} /></li>
          <li><p className="m-0 mb-2">Run it. The validator sends <code>Ready</code> once its connection is healthy and then works every round it is in the active set.</p><Command text="node v2/provider/anyhonest-validator.mjs run validator.json" /></li>
        </ol>
        <p className="m-0 mb-2">To leave, exit and then finalize once the exit round has passed. Finalizing refunds your bond.</p>
        <Command text={"node v2/provider/anyhonest-validator.mjs exit validator.json\nnode v2/provider/anyhonest-validator.mjs finalize-exit validator.json"} />
      </Section>

      <Section title="Slashing, cooldown and rejoining">
        <ul className="m-0 list-disc space-y-1 pl-5">
          <li>Every missed commit or reveal costs {fmt(p.slash)} RNG of your bond, paid to the treasury, and suspends you.</li>
          <li>A withheld reveal is cracked by others; the {fmt(beacon?.priceSchedule?.crackBounty ?? 10)} RNG crack bounty is taken from your bond too.</li>
          <li>After a fault you must wait {duration(p.rejoinBaseMs)} before rejoining. The wait doubles with each incident, up to {duration(p.rejoinCapMs)}, and resets after you stay ready that long.</li>
          <li>To rejoin, your bond plus earnings must cover the full {fmt(p.stake)} RNG stake again. Top up before you send <code>Ready</code>; the validator does this check itself.</li>
          <li>Governance can remove a validator, but it always refunds the full bond. It cannot take bonds.</li>
        </ul>
      </Section>

      <Section title="Expected earnings">
        <p className="m-0">Each round pays {fmt(roundPrice)} RNG from the reserve, split across the active set, at about {fmt(rate, 1)} rounds per second. Each request adds {fmt(requestPrice - 1)} RNG split across the round&apos;s contributors.</p>
        <dl className="m-0 grid grid-cols-1 gap-2 sm:grid-cols-2">
          <Stat label={`If you join now (${fmt(active + 1)} active)`} value={`≈ ${fmt(now.perDay)} RNG/day · bond repaid in ${duration((p.stake / now.perSecond) * 1000)}`} />
          <Stat label={`With a full set (${fmt(p.maxActive)} active)`} value={`≈ ${fmt(full.perDay)} RNG/day · bond repaid in ${duration((p.stake / full.perSecond) * 1000)}`} />
        </dl>
        <p className="m-0">These are heartbeat estimates, not promises. Pay falls as more validators join. When the reserve runs out, the beacon only runs rounds for paid requests and pay drops to the request share.</p>
      </Section>

      <Section title="Risks">
        <ul className="m-0 list-disc space-y-1 pl-5">
          <li>Downtime and slow links cost {fmt(p.slash)} RNG per missed duty, plus a growing cooldown.</li>
          <li>Lost round secrets mean a slash for every round you had open.</li>
          <li>A lost wallet means a lost bond. Nobody can recover it for you.</li>
          <li>The RNG DAO can change parameters such as stake, slash and prices, within fixed hard bounds.</li>
          <li>RNG price risk: your bond and earnings are in RNG.</li>
        </ul>
      </Section>
    </div>
  );
}
