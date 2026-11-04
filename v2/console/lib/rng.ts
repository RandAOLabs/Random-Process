import { bls12_381 as bls } from "@noble/curves/bls12-381.js";
import { env } from "cloudflare:workers";

const encoder = new TextEncoder();

export type Member = { address: string; index: number; "public-key"?: string };
export type Round = { signature: string; value: string; signers: string[] };
export type BeaconInfo = {
  committee: Member[];
  groupKey: string;
  pendingCount: number;
  price: { beacon: number };
  protocolAccrued: number;
  round: number;
  threshold: number;
  token: string;
  unit: number;
  verification: "attestations" | "device";
};
type BeaconState = { self: string; rounds: Record<string, Round> };
type AccountBeaconState = BeaconState & { balances: Record<string, number> };
type TokenInfo = { Denomination: string; FaucetAmount: string; FaucetLifetimeCap: string; Ticker: string };

export function networkConfig() {
  const node = env.RNG_NODE_URL;
  const beacon = env.RNG_BEACON_ID;
  const token = env.RNG_TOKEN_ID;
  if (!node || !beacon || !token) throw new Error("RNG network configuration is incomplete");
  return { node: node.replace(/\/$/, ""), beacon, token, label: env.RNG_NETWORK_LABEL || "Testnet" };
}

export function extendedNetworkConfig() {
  const cfg = networkConfig();
  return { ...cfg, anyHonest: env.RNG_ANYHONEST_ID || "", dao: env.RNG_DAO_ID || "" };
}

async function readJson<T>(url: string, accept = "application/ao"): Promise<T> {
  // HyperBEAM's `application/json` codec wraps process bodies in
  // `{ "ao-result": "body", body: "..." }`. The AO representation returns
  // the process/device JSON itself, which is the stable shape callers need.
  const response = await fetch(url, { cache: "no-store", headers: { accept }, signal: AbortSignal.timeout(8_000) });
  if (!response.ok) throw new Error(`HyperBEAM returned HTTP ${response.status}`);
  return response.json() as Promise<T>;
}

export async function getAnyHonestStatus() {
  const cfg = extendedNetworkConfig();
  if (!cfg.anyHonest) return { configured: false, status: "not-deployed" };
  const base = `${cfg.node}/${cfg.anyHonest}~process@1.0/now`;
  type Output = { y: string; via: "reveal" | "crack"; alpha?: string; proof?: string };
  type Record = { T: number; h: string; commits: { [address: string]: string };
    outputs: { [address: string]: Output }; value: string; opened?: number; finalizedAt?: number };
  type Info = { round: number; unit: number; validators: Array<{ suspended?: boolean; exiting?: boolean }>;
    foundationReserveAtoms: string; treasuryAtoms: string; activeSubscriptions: number;
    priceSchedule: { round: number; request: number; subscription: number; subscriptionRounds: number; crackBounty: number } };
  type State = { rounds: { [round: string]: Record } };
  type Recent = Array<{ round: number; value: string; opened?: number; finalizedAt?: number }>;
  const info = await readJson<Info>(`${base}/beaconinfo`);
  // A lua-patch@1.0 beacon publishes each finalized round in its own key and
  // checkpoints the full state only now and then; older beacons publish the
  // rounds inside timelockstate on every message.
  const [own, recentKey] = await Promise.all([
    readJson<Record & { round: number }>(`${base}/beaconround-${info.round % 8}`).catch(() => null),
    readJson<Recent>(`${base}/beaconrecent`).catch(() => null),
  ]);
  const state = own && own.round === info.round && Array.isArray(recentKey)
    ? null : await readJson<State>(`${base}/timelockstate`);
  const record = state ? state.rounds[String(info.round)] : own ?? undefined;
  let proofValid = Boolean(record);
  if (record) {
    const addresses = Object.keys(record.commits).sort();
    // Each output verifies independently, so check them concurrently.
    const checks = await Promise.all(addresses.map(async (address) => {
      const output = record.outputs[address];
      if (!output) return false;
      const url = new URL(`${cfg.node}/~rng@1.0/${output.via === "reveal" ? "verify-reveal" : "verify-crack"}`);
      if (output.via === "reveal") {
        url.searchParams.set("c", record.commits[address]);
        url.searchParams.set("alpha", output.alpha ?? "");
        url.searchParams.set("h", record.h);
      } else {
        url.searchParams.set("x", record.commits[address]);
        url.searchParams.set("t", String(record.T));
        url.searchParams.set("y", output.y);
        url.searchParams.set("proof", output.proof ?? "");
      }
      const result = await readJson<{ valid?: boolean | string; y?: string }>(url.toString(), "application/json");
      return [true, "true"].includes(result.valid ?? false) && result.y === output.y;
    }));
    proofValid = checks.every(Boolean);
    if (proofValid) {
      const ys = addresses.map((address) => record.outputs[address].y).join("|");
      const expected = await sha256Hex(`hyperbeam/rng/any-honest/v1/round|${cfg.anyHonest}|${info.round}|${ys}`);
      proofValid = expected === record.value;
    }
  }
  // The process keeps its last few finalized rounds; clients use them to fill
  // in rounds that finalized between polls.
  const recent = (state
    ? Object.entries(state.rounds).map(([round, r]) => ({ round: Number(round), value: r.value,
      opened: r.opened, finalizedAt: r.finalizedAt }))
    : [...(recentKey ?? [])])
    .sort((a, b) => b.round - a.round);
  return { configured: true, process: cfg.anyHonest, ...info, latest: record, recent,
    proofValid, checkedAt: new Date().toISOString() };
}

export async function getGovernanceStatus() {
  const cfg = extendedNetworkConfig();
  if (!cfg.dao) return { configured: false, status: "not-deployed", proposals: [] };
  type ProposalState = { id?: number | string; eligible?: Record<string, unknown>;
    voters?: Record<string, unknown>; [key: string]: unknown };
  const state = await readJson<{
    totalStaked?: number; quorumBps?: number; votingPeriodMs?: number;
    minProposalStake?: number; proposals?: Record<string, ProposalState>;
  }>(`${cfg.node}/${cfg.dao}~process@1.0/now/daostate`);
  const proposals = Object.values(state.proposals ?? {}).map((proposal) => {
    const voters = proposal.voters && typeof proposal.voters === "object"
      ? Object.keys(proposal.voters as Record<string, unknown>).length : 0;
    const { eligible: _eligible, voters: _voters, ...publicProposal } = proposal;
    void _eligible; void _voters;
    return { ...publicProposal, voters };
  }).sort((a, b) => Number(b.id ?? 0) - Number(a.id ?? 0));
  return { configured: true, process: cfg.dao, token: cfg.token, unit: 1000000,
    totalStaked: state.totalStaked ?? 0,
    quorumBps: state.quorumBps ?? 0, votingPeriodMs: state.votingPeriodMs ?? 0,
    minProposalStake: state.minProposalStake ?? 0, proposals };
}

export async function sha256Hex(bytes: Uint8Array | string) {
  const input = typeof bytes === "string" ? encoder.encode(bytes) : bytes;
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", input as unknown as BufferSource),
  );
  return Array.from(digest, (value) => value.toString(16).padStart(2, "0")).join("");
}

export function verifySignature(publicKey: string, message: string, signature: string) {
  const sigs = bls.longSignatures;
  return sigs.verify(
    bls.G2.Point.fromHex(signature),
    sigs.hash(encoder.encode(message)),
    bls.G1.Point.fromHex(publicKey),
  );
}

export async function deriveBytes(seed: string, counter: number, byteCount: number) {
  if (!Number.isSafeInteger(counter) || counter < 0) throw new Error("counter must be a non-negative integer");
  if (!Number.isSafeInteger(byteCount) || byteCount < 1 || byteCount > 1024) throw new Error("bytes must be between 1 and 1024");
  const seedBytes = encoder.encode(seed);
  const prefix = encoder.encode(`hyperbeam/rng/v1/derive|${seedBytes.length}|`);
  const output: number[] = [];
  for (let block = counter; output.length < byteCount; block += 1) {
    const suffix = encoder.encode(`|${block}`);
    const input = new Uint8Array(prefix.length + seedBytes.length + suffix.length);
    input.set(prefix);
    input.set(seedBytes, prefix.length);
    input.set(suffix, prefix.length + seedBytes.length);
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", input));
    output.push(...digest);
  }
  return Array.from(output.slice(0, byteCount), (value) => value.toString(16).padStart(2, "0")).join("");
}

export async function getNetworkStatus(requestedRound?: number) {
  const cfg = networkConfig();
  const processBase = `${cfg.node}/${cfg.beacon}~process@1.0/now`;
  const tokenBase = `${cfg.node}/${cfg.token}~process@1.0/now`;
  const [info, state, tokenInfo] = await Promise.all([
    readJson<BeaconInfo>(`${processBase}/beaconinfo`),
    readJson<BeaconState>(`${processBase}/beaconstate`),
    readJson<TokenInfo>(`${tokenBase}/tokeninfo`),
  ]);
  const roundNumber = requestedRound ?? info.round;
  const round = state.rounds[String(roundNumber)];
  if (!round) throw new Error(`round ${roundNumber} is not available in retained history`);
  const message = `hyperbeam/rng/v1|${state.self}|${roundNumber}`;
  const expectedValue = await sha256Hex(`hyperbeam/rng/v1/round|${message}|${round.signature.toLowerCase()}`);
  let signatureValid = false;
  try { signatureValid = verifySignature(info.groupKey, message, round.signature); } catch { signatureValid = false; }
  const denomination = 10 ** Number(tokenInfo.Denomination || 0);
  return {
    network: cfg.label,
    beacon: cfg.beacon,
    token: cfg.token,
    round: roundNumber,
    latestRound: info.round,
    threshold: info.threshold,
    committeeSize: info.committee.length,
    committee: info.committee,
    price: info.price.beacon,
    unit: info.unit,
    pending: info.pendingCount,
    verificationMode: info.verification,
    nativeVerification: info.verification === "device",
    groupKey: info.groupKey,
    message,
    signature: round.signature,
    value: round.value,
    signers: round.signers,
    signatureValid,
    valueValid: expectedValue === round.value,
    verified: signatureValid && expectedValue === round.value,
    tokenInfo: {
      ticker: tokenInfo.Ticker,
      faucetAmount: Number(tokenInfo.FaucetAmount) / denomination,
      faucetLifetimeCap: Number(tokenInfo.FaucetLifetimeCap) / denomination,
    },
    checkedAt: new Date().toISOString(),
  };
}

export async function getAccountStatus(address: string) {
  if (!/^[A-Za-z0-9_-]{43}$/.test(address)) throw new Error("address must be a 43-character AO address");
  const cfg = networkConfig();
  const [balances, beacon] = await Promise.all([
    readJson<Record<string, string>>(`${cfg.node}/${cfg.token}~process@1.0/now/balances`),
    readJson<AccountBeaconState>(`${cfg.node}/${cfg.beacon}~process@1.0/now/beaconstate`),
  ]);
  const info = await readJson<BeaconInfo>(`${cfg.node}/${cfg.beacon}~process@1.0/now/beaconinfo`);
  return {
    address,
    tokenBalance: Number(balances[address] ?? 0) / info.unit,
    beaconBalance: Number(beacon.balances[address] ?? 0),
    price: info.price.beacon,
    unit: info.unit,
  };
}
