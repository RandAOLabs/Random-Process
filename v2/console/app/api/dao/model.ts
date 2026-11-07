// The stake-dao/1 shapes the RNG DAO publishes and the beacon's governance
// queue, with the arithmetic the /dao page shows. Pure: no network, no wallet.
// Tally mirrors YapDAO's dao.lua `outcome` (paralith-mono dao-model.ts).

export type DaoInfo = {
  Standard: string; Name: string; Token: string; Ticker: string; Denomination: number; Admin: string;
  ProposalThreshold: string; ProposalDeposit: string; ProposalRequirement?: string;
  VotingPeriod: number; QuorumBps: number; PassBps: number; VetoBps: number; UnstakeDelay: number;
  MaxActiveProposals: number; TotalStaked: string; TotalCooling: string; Stakers: number;
  Proposals: number; OpenProposals: number; Configured: boolean; Problem?: string;
};

export type DaoStatus = "active" | "passed" | "rejected" | "vetoed" | "failed-quorum" | "cancelled";

export type DaoProposal = {
  id: string; proposer: string; title: string; body?: string; link?: string; status: DaoStatus;
  createdAt: number; endsAt: number; closedAt?: number; quorum: string;
  yes: string; no: string; abstain: string; veto: string; passBps: number; vetoBps: number; voters: number;
  /** The one tags-only message a passed proposal sends when it closes (Exec-Process / Exec-Tags). */
  action?: { process: string; tags: Record<string, string>; executed: boolean; executedAt?: number };
};

export type DaoStake = { active: string; cooling: string; releaseAt: number; lockedUntil: number; votes?: Record<string, string> };

/** A beacon Gov.* action waiting out its timelock (beaconinfo.govQueue, v3). */
export type GovQueueEntry = { id: number; kind: string; at: number; queuedAt: number; [field: string]: unknown };

const BPS = BigInt(10_000);
const big = (value: string | number | undefined) => {
  try { return BigInt(String(value ?? 0)); } catch { return BigInt(0); }
};
const shareFloor = (x: bigint, bps: number) => (x * BigInt(bps)) / BPS;

/** The status a proposal would close with if voting ended now. */
export function tally(p: Pick<DaoProposal, "yes" | "no" | "abstain" | "veto" | "quorum" | "passBps" | "vetoBps">) {
  const yes = big(p.yes), no = big(p.no), abstain = big(p.abstain), veto = big(p.veto);
  const total = yes + no + abstain + veto;
  const quorum = big(p.quorum);
  const quorumMet = total >= quorum;
  const outcome = !quorumMet ? "failed-quorum"
    : veto > shareFloor(total, p.vetoBps ?? 10_000) ? "vetoed"
      : yes > shareFloor(yes + no + veto, p.passBps ?? 0) ? "passed" : "rejected";
  return { yes, no, abstain, veto, total, quorum, quorumMet, outcome };
}

/** Atoms as whole tokens, truncated, with thousands separators. */
export function tokens(atoms: string | undefined, denomination = 6) {
  if (atoms === undefined || !/^\d+$/.test(atoms)) return "—";
  return (BigInt(atoms) / BigInt(10) ** BigInt(denomination)).toLocaleString("en-US");
}

export const percent = (bps: number) => `${(bps / 100).toFixed(bps % 100 ? 2 : 0)}%`;

export function duration(ms: number) {
  const units: Array<[string, number]> = [["d", 86_400_000], ["h", 3_600_000], ["min", 60_000], ["s", 1000]];
  for (const [unit, size] of units) if (ms >= size) return `${Math.floor(ms / size)} ${unit}`;
  return "0 s";
}

/** Where the RNG DAO is voted on. */
export const yapUrl = (dao: string) => `https://yapdao.com/?dao=${encodeURIComponent(dao)}`;

/** A proposal's action as one readable line, flagged when it targets the beacon. */
export function describeAction(action: DaoProposal["action"], beacon: string) {
  if (!action) return null;
  const { Action: name = "(no Action tag)", ...rest } = action.tags ?? {};
  const args = Object.entries(rest).map(([k, v]) => `${k}=${v}`).join(" ");
  return { name, args, toBeacon: Boolean(beacon) && action.process === beacon, executed: action.executed };
}

/** The beacon's queued Gov.* actions, soonest first, with whether Gov.Apply can run now. */
export function queueView(queue: GovQueueEntry[] | undefined, now: number) {
  return [...(queue ?? [])].sort((a, b) => a.at - b.at).map((e) => {
    const { id, kind, at, queuedAt, ...detail } = e;
    return { id, kind, at, queuedAt, due: now >= at, remainingMs: Math.max(0, at - now),
      detail: Object.entries(detail).map(([k, v]) => `${k}=${typeof v === "string" ? v : JSON.stringify(v)}`).join(" ") };
  });
}
