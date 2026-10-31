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

async function readJson<T>(url: string): Promise<T> {
  const response = await fetch(url, { cache: "no-store", signal: AbortSignal.timeout(8_000) });
  if (!response.ok) throw new Error(`HyperBEAM returned HTTP ${response.status}`);
  return response.json() as Promise<T>;
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
