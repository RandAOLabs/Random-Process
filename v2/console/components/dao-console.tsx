"use client";

import { useState } from "react";
import { useLivePoll } from "../hooks/use-live-poll";
import { connectWallet, sendMessage } from "../lib/wallet";
import { SiteFooter, SiteHeader } from "./site-header";

type Proposal = { id?: number; title?: string; summary?: string; kind?: string; status?: string;
  yes?: number; no?: number; abstain?: number; eligiblePower?: number; voters?: number };
type DaoStatus = { configured: boolean; process?: string; token?: string; unit?: number;
  totalStaked?: number; quorumBps?: number; votingPeriodMs?: number; minProposalStake?: number;
  proposals: Proposal[]; error?: string };
type AnyHonestStatus = { configured: boolean; round?: number; foundationReserveAtoms?: string;
  treasuryAtoms?: string; unit?: number; activeSubscriptions?: number;
  priceSchedule?: { round?: number; request?: number; subscription?: number; subscriptionRounds?: number; crackBounty?: number } };

export function DaoConsole() {
  const [dao, setDao] = useState<DaoStatus>({ configured: false, proposals: [] });
  const [beacon, setBeacon] = useState<AnyHonestStatus>({ configured: false });
  const [address, setAddress] = useState<string | null>(null);
  const [selected, setSelected] = useState<number | null>(null);
  const [stake, setStake] = useState("1000");
  const [title, setTitle] = useState("");
  const [summary, setSummary] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function refresh() {
    const [daoResponse, beaconResponse] = await Promise.all([
      fetch("/api/dao", { cache: "no-store" }), fetch("/api/anyhonest", { cache: "no-store" }),
    ]);
    setDao(await daoResponse.json() as DaoStatus);
    setBeacon(await beaconResponse.json() as AnyHonestStatus);
  }

  useLivePoll(refresh);

  async function action(label: string, run: () => Promise<void>) {
    setBusy(label); setError(null);
    try { await run(); await refresh(); }
    catch (problem) { setError(problem instanceof Error ? problem.message : String(problem)); }
    finally { setBusy(null); }
  }

  const connect = () => action("CONNECTING", async () => { setAddress(await connectWallet()); });
  const fundStake = () => action("STAKING", async () => {
    if (!address || !dao.configured || !dao.process || !dao.token) throw new Error("connect after the DAO is deployed");
    const amount = Number(stake);
    if (!Number.isSafeInteger(amount) || amount < 1) throw new Error("stake must be a positive whole RNG amount");
    await sendMessage(dao.token, { Action: "Transfer", Recipient: dao.process,
      Quantity: String(amount * (dao.unit ?? 1000000)), "X-For": address, "X-Governance": "true" });
  });
  const propose = () => action("PROPOSING", async () => {
    if (!dao.configured || !dao.process || !title.trim()) throw new Error("DAO deployment and a title are required");
    await sendMessage(dao.process, { Action: "Propose",
      Data: JSON.stringify({ title: title.trim(), summary: summary.trim(), kind: "general" }) });
    setTitle(""); setSummary("");
  });
  const vote = (choice: "yes" | "no" | "abstain") => action(`VOTING_${choice.toUpperCase()}`, async () => {
    if (!dao.configured || !dao.process || !selected) throw new Error("select a proposal first");
    await sendMessage(dao.process, { Action: "Vote", Data: JSON.stringify({ id: selected, choice }) });
  });

  const unit = BigInt(beacon.unit ?? 1000000);
  const rng = (atoms?: string) => atoms ? (BigInt(atoms) / unit).toString() : "—";
  const chosen = dao.proposals.find((proposal) => proposal.id === selected);

  return (
    <main className="shell compact-page dao-page">
      <SiteHeader active="dao" />
      <section className="page-titlebar container"><div><p className="kicker">[ 04 // DAO ]</p><h1>Vote. Admins execute.</h1></div><p>Governance is advisory by design. Passed proposals never move funds or upgrade contracts automatically.</p></section>
      <section className="dao-board container">
        <div className="dao-column"><p className="board-label">PROTOCOL_FUNDS</p><dl className="dao-metrics"><div><dt>FOUNDATION_RESERVE</dt><dd>{rng(beacon.foundationReserveAtoms)} RNG</dd></div><div><dt>DAO_TREASURY</dt><dd>{rng(beacon.treasuryAtoms)} RNG</dd></div><div><dt>BEACON_ROUND</dt><dd>{beacon.round ?? "—"}</dd></div><div><dt>STAKED_VOTING_POWER</dt><dd>{dao.totalStaked ?? 0} RNG</dd></div></dl><p className="dao-rule">Foundation pays heartbeat rounds. Treasury receives subscriptions and pays 10 RNG crack bounties.</p></div>
        <div className="dao-column"><p className="board-label">PROPOSALS</p><div className="proposal-list">{dao.proposals.length === 0 ? <p className="muted">{dao.configured ? "NO_PROPOSALS" : "DAO_PROCESS_NOT_DEPLOYED"}</p> : dao.proposals.slice(0, 4).map((proposal) => <button key={proposal.id} className={selected === proposal.id ? "proposal selected" : "proposal"} onClick={() => setSelected(proposal.id ?? null)}><span>#{proposal.id} · {proposal.status}</span><b>{proposal.title}</b><small>YES {proposal.yes ?? 0} / NO {proposal.no ?? 0} / ABSTAIN {proposal.abstain ?? 0}</small></button>)}</div>{chosen && <div className="vote-row"><button onClick={() => void vote("yes")}>YES</button><button onClick={() => void vote("no")}>NO</button><button onClick={() => void vote("abstain")}>ABSTAIN</button></div>}</div>
        <div className="dao-column"><p className="board-label">PARTICIPATE</p><button className="button" onClick={connect} disabled={Boolean(busy)}>{address ? `${address.slice(0, 8)}...CONNECTED` : "CONNECT_WANDER"}</button><label className="field compact"><span>STAKE RNG</span><input value={stake} onChange={(event) => setStake(event.target.value)} /></label><button className="button" onClick={fundStake} disabled={!address || !dao.configured || Boolean(busy)}>STAKE_FOR_VOTING</button><label className="field compact"><span>PROPOSAL TITLE</span><input value={title} onChange={(event) => setTitle(event.target.value)} maxLength={120} /></label><label className="field compact"><span>SUMMARY</span><input value={summary} onChange={(event) => setSummary(event.target.value)} maxLength={4000} /></label><button className="button invert" onClick={propose} disabled={!address || !dao.configured || Boolean(busy)}>SUBMIT_PROPOSAL</button>{busy && <p className="notice">{busy}</p>}{error && <p className="error">{error}</p>}</div>
      </section>
      <SiteFooter />
    </main>
  );
}
