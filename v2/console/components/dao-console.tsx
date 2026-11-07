"use client";

import { useState, type CSSProperties, type ReactNode } from "react";
import { useLivePoll } from "../hooks/use-live-poll";
import { connectWallet, sendMessage } from "../lib/wallet";
import {
  describeAction, duration, percent, queueView, tally, tokens, yapUrl,
  type DaoInfo, type DaoProposal, type DaoStake, type GovQueueEntry,
} from "../app/api/dao/model";
import { SiteFooter, SiteHeader } from "./site-header";

type DaoStatus = { configured: boolean; status?: string; process?: string; beacon?: string;
  info?: DaoInfo; proposals: DaoProposal[]; error?: string };
// beaconinfo via /api/anyhonest. The v3 governance fields are absent on a v2 beacon.
type Beacon = { configured: boolean; process?: string; round?: number; unit?: number;
  foundationReserveAtoms?: string; treasuryAtoms?: string; mode?: string; paused?: boolean;
  governor?: string; successor?: string; successorAck?: boolean;
  govQueue?: GovQueueEntry[]; features?: string[] };

const h1: CSSProperties = { fontFamily: "var(--display)", fontSize: 30, lineHeight: 1.2, letterSpacing: "-.01em", textTransform: "none" };
const h2: CSSProperties = { fontFamily: "var(--display)", fontSize: 20, lineHeight: 1.3, letterSpacing: 0, textTransform: "none", marginBottom: 12 };
const short = (a?: string) => a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "—";
const when = (ms?: number) => ms ? new Date(ms).toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short" }) : "—";

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="border-t border-[var(--line)] py-8">
      <h2 style={h2}>{title}</h2>
      <div className="space-y-3 text-[14px] leading-relaxed text-[var(--gray)]">{children}</div>
    </section>
  );
}

function Stat({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="border border-[var(--line)] bg-[#0c0c0c] p-3">
      <dt className="text-[11px] text-[var(--dim)]">{label}</dt>
      <dd className="m-0 mt-1 break-all text-[15px] text-[var(--white)] tabular-nums">{value}</dd>
    </div>
  );
}

export function DaoConsole() {
  const [dao, setDao] = useState<DaoStatus>({ configured: false, proposals: [] });
  const [beacon, setBeacon] = useState<Beacon>({ configured: false });
  const [now, setNow] = useState(0);
  const [address, setAddress] = useState<string | null>(null);
  const [stake, setStake] = useState<DaoStake | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function refresh() {
    const [daoResponse, beaconResponse] = await Promise.all([
      fetch("/api/dao", { cache: "no-store" }), fetch("/api/anyhonest", { cache: "no-store" }),
    ]);
    setDao(await daoResponse.json() as DaoStatus);
    setBeacon(await beaconResponse.json() as Beacon);
    setNow(Date.now());
  }

  useLivePoll(refresh, 5_000);

  async function action(label: string, run: () => Promise<void>) {
    setBusy(label); setError(null);
    try { await run(); await refresh(); }
    catch (problem) { setError(problem instanceof Error ? problem.message : String(problem)); }
    finally { setBusy(null); }
  }

  const connect = () => action("Connecting", async () => {
    const next = await connectWallet();
    setAddress(next);
    const response = await fetch(`/api/dao?address=${encodeURIComponent(next)}`, { cache: "no-store" });
    const body = await response.json() as { stake?: DaoStake; error?: string };
    if (!response.ok) throw new Error(body.error || "stake unavailable");
    setStake(body.stake ?? null);
  });
  // Gov.Apply is open to anyone once a queued action's timelock has passed.
  const apply = (id: number) => action(`Applying #${id}`, async () => {
    if (!beacon.process) throw new Error("the beacon is not configured");
    if (!address) setAddress(await connectWallet());
    const reply = (await sendMessage(beacon.process, { Action: "Gov.Apply", "Gov-Id": String(id) })).reply;
    if (typeof reply?.error === "string") throw new Error(reply.error);
  });

  const info = dao.info;
  const denom = info?.Denomination ?? 6;
  const unitDigits = Math.round(Math.log10(beacon.unit ?? 1_000_000));
  const v3 = beacon.features?.includes("gov") ?? false;
  const queue = queueView(beacon.govQueue, now);
  const beaconPid = dao.beacon || beacon.process || "";

  return (
    <main className="shell">
      <SiteHeader active="dao" />
      <div className="container pb-24">
        <section className="py-10">
          <h1 style={h1}>RNG DAO</h1>
          <div className="mt-4 max-w-[760px] space-y-3 text-[15px] leading-relaxed text-[var(--gray)]">
            <p className="m-0">RNG holders govern the beacon through a YapDAO <code>stake-dao/1</code> process. Stake RNG to vote. A passed proposal sends one message, usually a <code>Gov.*</code> action to the beacon. Actions that move money wait out a 10-day timelock in the beacon first, longer than the 7-day vote, so a cancelling proposal can always pass before they land. There is no guardian: pausing is a proposal too.</p>
            <p className="m-0">This page is read-only. Staking, proposing and voting happen on YapDAO.</p>
            {dao.process && <p className="m-0"><a className="button invert" href={yapUrl(dao.process)} target="_blank" rel="noreferrer">Vote on yapdao.com</a></p>}
          </div>
        </section>

        <Section title="Beacon governance">
          {!beacon.configured && <p className="m-0">The beacon is not deployed on this network yet.</p>}
          {beacon.configured && !v3 && <p className="m-0">This beacon predates DAO governance. The fields below fill in once beacon v3 is live.</p>}
          <dl className="m-0 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
            <Stat label="Governor" value={v3 ? (beacon.governor ? short(beacon.governor) : "Deployer, until handover") : "—"} />
            <Stat label="Mode" value={beacon.paused ? "Paused" : beacon.mode ?? "—"} />
            <Stat label="Reserve" value={`${tokens(beacon.foundationReserveAtoms, unitDigits)} RNG`} />
            <Stat label="Treasury" value={`${tokens(beacon.treasuryAtoms, unitDigits)} RNG`} />
            <Stat label="Successor" value={beacon.successor ? `${short(beacon.successor)}${beacon.successorAck ? " (acked)" : ""}` : "None"} />
          </dl>
        </Section>

        <Section title="Timelocked actions">
          <p className="m-0">Set-Successor and Move-Reserve wait 7 days, Treasury-Spend 48 hours. Anyone can apply an action once its time has come; the DAO can cancel it before then.</p>
          {queue.length === 0 ? <p className="m-0">Nothing is queued.</p> : (
            <table className="w-full border-collapse text-[13px]">
              <thead><tr className="text-left text-[var(--dim)]"><th className="py-1 pr-3">#</th><th className="py-1 pr-3">Action</th><th className="py-1 pr-3">Details</th><th className="py-1 pr-3">Runs</th><th /></tr></thead>
              <tbody>{queue.map((e) => (
                <tr key={e.id} className="border-t border-[var(--line)]">
                  <td className="py-2 pr-3">{e.id}</td>
                  <td className="py-2 pr-3 text-[var(--white)]">{e.kind}</td>
                  <td className="py-2 pr-3 break-all">{e.detail || "—"}</td>
                  <td className="py-2 pr-3">{e.due ? "Now" : `in ${duration(e.remainingMs)} (${when(e.at)})`}</td>
                  <td className="py-2">{e.due && <button className="button" onClick={() => void apply(e.id)} disabled={Boolean(busy)}>Apply</button>}</td>
                </tr>))}</tbody>
            </table>)}
        </Section>

        <Section title="The DAO">
          {!dao.configured && <p className="m-0">{dao.status === "not-stake-dao" ? "The configured DAO process is not a stake-dao/1 DAO." : "The RNG DAO is not deployed on this network yet."}</p>}
          {info && <>
            <dl className="m-0 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
              <Stat label="Staked" value={`${tokens(info.TotalStaked, denom)} ${info.Ticker}`} />
              <Stat label="Stakers" value={info.Stakers} />
              <Stat label="Open proposals" value={`${info.OpenProposals} / ${info.MaxActiveProposals}`} />
              <Stat label="To propose" value={`${tokens(info.ProposalRequirement ?? info.ProposalThreshold, denom)} staked + ${tokens(info.ProposalDeposit, denom)} deposit`} />
              <Stat label="Voting period" value={duration(info.VotingPeriod)} />
              <Stat label="Unstake delay" value={duration(info.UnstakeDelay)} />
            </dl>
            <p className="m-0">Quorum {percent(info.QuorumBps)} of staked RNG. A proposal passes with more than {percent(info.PassBps)} yes, and is vetoed above {percent(info.VetoBps)} veto.</p>
          </>}
          {address && <p className="m-0">Your stake ({short(address)}): {tokens(stake?.active ?? "0", denom)} active, {tokens(stake?.cooling ?? "0", denom)} cooling{stake?.releaseAt ? `, withdrawable ${when(stake.releaseAt)}` : ""}.</p>}
          {!address && dao.configured && <button className="button" onClick={() => void connect()} disabled={Boolean(busy)}>Show my stake</button>}
        </Section>

        <Section title="Proposals">
          {dao.proposals.length === 0 && <p className="m-0">No proposals yet.</p>}
          <div className="space-y-3">{dao.proposals.slice(0, 20).map((p) => {
            const t = tally(p);
            const act = describeAction(p.action, beaconPid);
            return (
              <article key={p.id} className="border border-[var(--line)] p-4">
                <p className="m-0 text-[12px] text-[var(--dim)]">#{p.id} · {p.status}{p.status === "active" ? ` · ends ${when(p.endsAt)} · would be ${t.outcome}` : ""}</p>
                <p className="m-0 mt-1 text-[15px] text-[var(--white)]">{p.title}</p>
                <p className="m-0 mt-1 text-[12px]">Yes {tokens(p.yes, denom)} · No {tokens(p.no, denom)} · Veto {tokens(p.veto, denom)} · Abstain {tokens(p.abstain, denom)} · quorum {t.quorumMet ? "met" : `${tokens(p.quorum, denom)} needed`} · {p.voters} voters</p>
                {act && <p className="m-0 mt-2 break-all text-[12px]"><code>{act.name}</code> {act.args} → {act.toBeacon ? "beacon" : short(p.action?.process)}{act.executed ? " · executed" : ""}</p>}
                {dao.process && p.status === "active" && <p className="m-0 mt-2 text-[12px]"><a className="underline underline-offset-2" href={yapUrl(dao.process)} target="_blank" rel="noreferrer">Vote on YapDAO</a></p>}
              </article>);
          })}</div>
        </Section>
        {busy && <p className="notice" role="status">{busy}…</p>}
        {error && <p className="error" role="alert">{error}</p>}
      </div>
      <SiteFooter />
    </main>
  );
}
