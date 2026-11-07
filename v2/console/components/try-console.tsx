"use client";

import { useEffect, useState } from "react";
import { useLivePoll } from "../hooks/use-live-poll";
import { findRequest, payAndRequestTags, type RequestRecord } from "../lib/fair-client";
import { connectWallet, hasWallet, sendMessage } from "../lib/wallet";
import { SiteFooter, SiteHeader } from "./site-header";

type Mode = "local" | "threshold" | "beacon" | "anyhonest" | "proof";
type Status = {
  network: string; beacon: string; token: string; round: number; price: number;
  unit: number; threshold: number; committeeSize: number; nativeVerification: boolean;
  groupKey: string; signature: string; message: string; value: string; verified: boolean;
};
type Account = { address: string; tokenBalance: number; beaconBalance: number; price: number; unit: number };
type Draw = { requestId: string; round: number; value?: string; verified?: boolean };
// v3 adds process/token/price/mode/features and per-request round records; a v2 beacon omits them.
type AnyHonestStatus = { configured: boolean; process?: string; token?: string; price?: number;
  mode?: string; features?: string[]; requestRecords?: RequestRecord[]; round?: number; proofValid?: boolean;
  foundationReserveAtoms?: string; treasuryAtoms?: string; unit?: number;
  activeSubscriptions?: number; validators?: Array<{ suspended?: boolean; exiting?: boolean }>;
  latest?: { value?: string }; priceSchedule?: { round?: number; request?: number; crackBounty?: number } };

const modes: Array<{ key: Mode; title: string; command: string; line: string; state: "LIVE" | "RESTORING" | "NOT LIVE" }> = [
  { key: "local", title: "LOCAL", command: "derive", line: "Deterministic bytes inside one process.", state: "LIVE" },
  { key: "threshold", title: "FAST", command: "request", line: "On-demand 2-of-3 threshold BLS: safe unless 2 of 3 operators collude.", state: "LIVE" },
  { key: "beacon", title: "BEACON", command: "follow", line: "Foundation-funded Any-Honest public pulse.", state: "LIVE" },
  { key: "anyhonest", title: "ANY-HONEST", command: "timelock", line: "Safe if any one validator is honest; slower.", state: "LIVE" },
  { key: "proof", title: "PROOF EXPLORER", command: "verify", line: "Inspect any retained round yourself.", state: "LIVE" },
];

export function TryConsole() {
  const [mode, setMode] = useState<Mode>("beacon");
  const [status, setStatus] = useState<Status | null>(null);
  const [anyHonest, setAnyHonest] = useState<AnyHonestStatus>({ configured: false });
  const [statusError, setStatusError] = useState<string | null>(null);
  const [seed, setSeed] = useState("loot-chest-42");
  const [derived, setDerived] = useState("");
  const [deriving, setDeriving] = useState(false);
  const [proofRound, setProofRound] = useState("");
  const [proof, setProof] = useState<Status | null>(null);
  const [proofBusy, setProofBusy] = useState(false);
  const [walletPresent, setWalletPresent] = useState(false);
  const [address, setAddress] = useState<string | null>(null);
  const [account, setAccount] = useState<Account | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [draw, setDraw] = useState<Draw | null>(null);
  const [paid, setPaid] = useState<{ requestId: string; round?: number; value?: string; valid?: boolean } | null>(null);

  async function refreshStatus(round?: number) {
    const response = await fetch(`/api/status${round ? `?round=${round}` : ""}`, { cache: "no-store" });
    const body = await response.json() as Status & { error?: string };
    if (!response.ok) throw new Error(body.error || "status unavailable");
    if (!round) setStatus(body);
    return body;
  }

  async function refreshAnyHonest() {
    const response = await fetch("/api/anyhonest", { cache: "no-store" });
    const body = await response.json() as AnyHonestStatus & { error?: string };
    if (!response.ok) throw new Error(body.error || "Any-Honest status unavailable");
    setAnyHonest(body);
    return body;
  }

  useLivePoll(() => Promise.all([refreshStatus(), refreshAnyHonest()]).then(() => setStatusError(null)).catch((problem) => setStatusError(problem instanceof Error ? problem.message : "status unavailable")));

  useEffect(() => {
    const wallet = window.setTimeout(() => setWalletPresent(hasWallet()), 0);
    return () => window.clearTimeout(wallet);
  }, []);

  async function derive() {
    setDeriving(true); setError(null);
    try {
      const response = await fetch("/api/derive", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ seed, bytes: 32, counter: 0 }) });
      const body = await response.json() as { value?: string; error?: string };
      if (!response.ok) throw new Error(body.error || "derivation failed");
      setDerived(body.value ?? "");
    } catch (problem) { setError(problem instanceof Error ? problem.message : "derivation failed"); }
    finally { setDeriving(false); }
  }

  async function inspectProof() {
    setProofBusy(true); setError(null);
    try {
      const requested = proofRound.trim() === "" ? undefined : Number(proofRound);
      if (requested !== undefined && (!Number.isSafeInteger(requested) || requested < 1)) throw new Error("round must be a positive integer");
      setProof(await refreshStatus(requested));
    } catch (problem) { setError(problem instanceof Error ? problem.message : "verification failed"); }
    finally { setProofBusy(false); }
  }

  async function refreshAccount(currentAddress = address) {
    if (!currentAddress) return null;
    const response = await fetch(`/api/account?address=${encodeURIComponent(currentAddress)}`, { cache: "no-store" });
    const body = await response.json() as Account & { error?: string };
    if (!response.ok) throw new Error(body.error || "account unavailable");
    setAccount(body);
    return body;
  }

  async function walletAction(label: string, action: () => Promise<void>) {
    setBusy(label); setError(null);
    try { await action(); }
    catch (problem) { setError(problem instanceof Error ? problem.message : String(problem)); }
    finally { setBusy(null); }
  }

  function rejectError(reply: Record<string, unknown>) {
    if (typeof reply.error === "string") throw new Error(reply.error);
  }

  const onConnect = () => walletAction("CONNECTING_WALLET", async () => {
    const next = await connectWallet(); setAddress(next); await refreshAccount(next);
  });
  const onFund = () => walletAction("FUNDING_FAST", async () => {
    if (!status || !address) throw new Error("connect a wallet first");
    rejectError((await sendMessage(status.token, { Action: "Transfer", Recipient: status.beacon, Quantity: String(status.price * 3 * status.unit), "X-For": address })).reply);
    await refreshAccount();
  });
  const onRequest = () => walletAction("WAITING_FOR_FAST_ROUND", async () => {
    if (!status || !address) throw new Error("connect a wallet first");
    const requestId = `console-${Date.now()}-${crypto.randomUUID().slice(0, 8)}`;
    // Tier "beacon" is the fast tier's internal id, accepted by the old and the new process.
    const reply = (await sendMessage(status.beacon, { Action: "Request-Random", Tier: "beacon", "Request-Id": requestId })).reply;
    rejectError(reply);
    const round = Number(reply.round);
    if (!Number.isSafeInteger(round) || round < 1) throw new Error("the fast tier did not assign a round");
    setDraw({ requestId, round });
    for (let attempt = 0; attempt < 60; attempt += 1) {
      try {
        const nextProof = await refreshStatus(round);
        const framed = new TextEncoder().encode(`hyperbeam/rng/v1/request|${nextProof.value}|${requestId}`);
        const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", framed as unknown as BufferSource));
        const value = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
        setDraw({ requestId, round, value, verified: nextProof.verified });
        await Promise.all([refreshStatus(), refreshAccount()]);
        return;
      } catch { await new Promise((resolve) => window.setTimeout(resolve, 500)); }
    }
    throw new Error(`round ${round} did not finalize within 30 seconds`);
  });

  // One message: a token Transfer to the beacon with X-Request-Id credits and
  // requests in the same slot. A wallet's value is only in the round record.
  const onPayAndRequest = () => walletAction("Requesting", async () => {
    const beacon = anyHonest;
    if (!beacon.process || !beacon.token || !beacon.unit) throw new Error("the beacon is not ready");
    if (!beacon.features?.includes("pay-and-request")) throw new Error("this beacon does not take one-message requests yet (beacon v3)");
    const who = address ?? await connectWallet();
    setAddress(who);
    const price = beacon.price ?? beacon.priceSchedule?.request ?? 4;
    const requestId = `console-${Date.now()}-${crypto.randomUUID().slice(0, 8)}`;
    setPaid({ requestId });
    rejectError((await sendMessage(beacon.token, payAndRequestTags(beacon.process, BigInt(price) * BigInt(beacon.unit), requestId, Date.now()))).reply);
    for (let attempt = 0; attempt < 120; attempt += 1) {
      const body = await refreshAnyHonest().catch(() => null);
      const found = body ? await findRequest(body.requestRecords, who, requestId) : null;
      if (found) { setPaid({ requestId, round: found.round, value: found.value, valid: found.valid }); return; }
      await new Promise((resolve) => window.setTimeout(resolve, 500));
    }
    throw new Error("no result within 60 seconds. If the beacon refused the request, the RNG stays in your beacon balance.");
  });

  const shownProof = proof ?? status;

  return (
    <main className="shell try-page">
      <SiteHeader active="try" />
      <section className="container product-switcher" aria-label="RNG products">{modes.map((item, index) => <button key={item.key} className={mode === item.key ? "product-option selected" : "product-option"} onClick={() => { setMode(item.key); setError(null); }} aria-pressed={mode === item.key}><span className="product-index">0{index + 1}</span><span className={item.state === "LIVE" ? "product-state live" : "product-state"}>{item.state}</span><strong>{item.title}</strong><small>{item.line}</small><code>$ rng {item.command}</code></button>)}</section>

      <section className="try-workspace container"><div className="mode-workbench">
        {mode === "local" && <div className="workbench-grid"><div><p className="kicker">[ 01 // LOCAL ]</p><h2>Predictable on purpose.</h2><p className="muted">Free, immediate and replay-safe. Use it when the sender learning the result creates no advantage.</p><label className="field"><span>SEED</span><input value={seed} onChange={(event) => setSeed(event.target.value)} maxLength={4096} /></label><button className="button invert" onClick={derive} disabled={deriving || !seed}>{deriving ? "DERIVING..." : "$ rng derive"}</button></div><div className="terminal"><div className="terminal-bar"><span>stdout</span><span>~rng@1.0/derive</span></div><div className="terminal-body"><p><span className="prompt">&gt;</span> bytes=32 counter=0</p><code className="big-output">{derived || "waiting_for_input"}</code></div></div></div>}

        {mode === "threshold" && <div><h2>Fast random</h2><p className="muted">Fast: 2-of-3 threshold BLS, about one message phase, safe unless 2 of 3 operators collude. Any-Honest: safe if any one validator is honest, slower. Fast is on demand, not a heartbeat: a round opens only when a paid request waits for it, and the committee signs nothing else. Better than local randomness, weaker than Any-Honest. One result costs {status?.price ?? 3} RNG; applications should prepay the balance so players never handle protocol credits.</p><ol className="wallet-steps"><li className={address ? "done" : "active"}><span>1</span><div><strong>CONNECT_WANDER</strong><small>{address ?? "authorize this console"}</small></div><button className="button" onClick={onConnect} disabled={Boolean(address) || Boolean(busy)}>{address ? "CONNECTED" : walletPresent ? "CONNECT" : "NO_WALLET"}</button></li><li className={(account?.tokenBalance ?? 0) >= ((status?.price ?? 3) * 3) ? "done" : address ? "active" : ""}><span>2</span><div><strong>GET_RNG</strong><small>wallet::{account?.tokenBalance ?? "—"}</small></div><button className="button" disabled title="RNG has a fixed supply and no faucet">Buy on Paralith (coming soon)</button></li><li className={(account?.beaconBalance ?? 0) >= (status?.price ?? 3) ? "done" : account ? "active" : ""}><span>3</span><div><strong>FUND_FAST</strong><small>credit::{account?.beaconBalance ?? "—"}</small></div><button className="button" onClick={onFund} disabled={!account || account.tokenBalance < ((status?.price ?? 3) * 3) || Boolean(busy)}>FUND_{(status?.price ?? 3) * 3}</button></li><li className={(account?.beaconBalance ?? 0) >= (status?.price ?? 3) ? "active" : ""}><span>4</span><div><strong>REQUEST_RANDOM</strong><small>cost::{status?.price ?? 3}_TEST-RNG</small></div><button className="button invert" onClick={onRequest} disabled={!account || account.beaconBalance < (status?.price ?? 3) || Boolean(busy)}>EXECUTE</button></li></ol>{!walletPresent && <p className="notice">WANDER_NOT_FOUND :: <a href="https://wander.app" target="_blank" rel="noreferrer">install wallet</a></p>}{busy && <p className="notice" role="status">{busy} :: approve in Wander if prompted</p>}{draw && <output className="proof-output"><strong>{draw.value ? "RESULT_RECEIVED" : `WAITING_FOR_ROUND_${draw.round}`}</strong>{draw.value && <><span>{draw.verified ? "[ NATIVE_PROOF::PASS ]" : "[ PROOF::UNKNOWN ]"}</span><code>{draw.value}</code><small>round::{draw.round} request::{draw.requestId}</small></>}</output>}</div>}

        {mode === "beacon" && <div className="workbench-grid"><div><p className="kicker">[ 03 // BEACON // DEFAULT ]</p><h2>The public pulse is moving.</h2><p className="muted">The RNG Foundation prepays one Any-Honest round every 5 seconds. Public reads are observable; paid process subscriptions are the canonical bound delivery path.</p><div className="fact-stack"><div><span>STATUS</span><b>{anyHonest.configured ? "LIVE" : "CONNECTING"}</b></div><div><span>SOURCE</span><b>ANY-HONEST</b></div><div><span>PROOF</span><b>{anyHonest.proofValid ? "VERIFIED" : "WAIT"}</b></div></div><button className="button invert" onClick={() => void refreshAnyHonest().catch((problem) => setStatusError(problem instanceof Error ? problem.message : "status unavailable"))}>REFRESH_PUBLIC_ROUND</button></div><div className="terminal"><div className="terminal-bar"><span>beacon.feed</span><span>{anyHonest.proofValid ? "PASS" : "WAIT"}</span></div><div className="terminal-body"><p>mode......... {anyHonest.mode ?? "heartbeat"}</p><p>round........ {anyHonest.round ?? "—"}</p><p>validators... {anyHonest.validators?.filter((validator) => !validator.suspended && !validator.exiting).length ?? "—"}</p><p>round-cost... {anyHonest.priceSchedule?.round ?? 1} RNG</p><p>reserve...... {anyHonest.foundationReserveAtoms && anyHonest.unit ? `${(BigInt(anyHonest.foundationReserveAtoms) / BigInt(anyHonest.unit)).toString()} RNG` : "—"}</p><code className="big-output">{anyHonest.latest?.value ?? statusError ?? "awaiting verified round"}</code></div></div></div>}

        {mode === "anyhonest" && <div className="roadmap-workbench"><div><p className="kicker">[ 04 // ANY-HONEST // LIVE ]</p><h2>Fair unless everyone colludes.</h2><p className="lede">Every validator commits a time-lock puzzle before reveals begin. One honest hidden contribution keeps the round unpredictable; a missing reveal can be cracked later without changing the result.</p><div className="roadmap-status">NATIVE_TESTNET::{anyHonest.proofValid ? "VERIFIED" : "CHECKING"}</div></div><div className="protocol-steps"><div><span>01</span><b>COMMIT</b><p>Validators lock fresh puzzle contributions.</p></div><div><span>02</span><b>REVEAL</b><p>Secrets open only after the commit window closes.</p></div><div><span>03</span><b>CRACK</b><p>Treasury pays a {anyHonest.priceSchedule?.crackBounty ?? 10} RNG verified-crack bounty.</p></div><div><span>04</span><b>COMBINE</b><p>Every canonical output becomes one round value.</p></div></div><div className="mt-6 max-w-[760px] space-y-3 text-[14px] leading-relaxed text-[var(--gray)]"><p className="m-0 text-[16px] text-[var(--white)]">Request one value</p><p className="m-0">One signed message pays {anyHonest.price ?? anyHonest.priceSchedule?.request ?? 4} RNG and binds your request to the round taking commits. Get RNG on the Paralith RNG/GOLD market (coming soon).</p><button className="button invert" onClick={onPayAndRequest} disabled={Boolean(busy) || !anyHonest.configured}>{busy === "Requesting" ? "Waiting for the round..." : address ? "Pay and request" : "Connect and request"}</button>{!anyHonest.features?.includes("pay-and-request") && anyHonest.configured && <p className="m-0">Available once beacon v3 is live.</p>}{paid && <output className="proof-output"><strong>{paid.value ? `Round ${paid.round}` : "Waiting for your round"}</strong>{paid.value && <><span>{paid.valid ? "Value recomputed from the round: match" : "Value does not match the round"}</span><code>{paid.value}</code></>}<small>request::{paid.requestId}</small></output>}</div><div className="device-paths"><code>~rng@1.0/generator</code><code>~rng@1.0/verify-reveal</code><code>~rng@1.0/verify-crack</code><code>~rng@1.0/derive</code></div></div>}

        {mode === "proof" && <div className="workbench-grid"><div><p className="kicker">[ 05 // PROOF_EXPLORER ]</p><h2>Do not trust the badge.</h2><p className="muted">Fetch a retained round, verify its BLS signature against the group key, then recompute the domain-separated value.</p><label className="field"><span>ROUND // BLANK MEANS LATEST</span><input type="number" min="1" inputMode="numeric" value={proofRound} onChange={(event) => setProofRound(event.target.value)} placeholder={String(status?.round ?? 1)} /></label><button className="button invert" onClick={inspectProof} disabled={proofBusy}>{proofBusy ? "VERIFYING..." : "$ rng verify --round"}</button></div><div className="terminal"><div className="terminal-bar"><span>proof.explorer</span><span>{shownProof?.verified ? "PASS" : "WAIT"}</span></div><div className="terminal-body"><p>round........ {shownProof?.round ?? "—"}</p><p>device....... {shownProof?.nativeVerification ? "~rng@1.0" : "pending"}</p><p>signature.... {shownProof?.signature?.slice(0, 32) ?? "—"}...</p><p>group-key.... {shownProof?.groupKey?.slice(0, 32) ?? "—"}...</p><p>value........ {shownProof?.value ?? "—"}</p><p className={shownProof?.verified ? "pass" : "wait"}>proof......... {shownProof?.verified ? "VERIFIED" : statusError ?? "PENDING"}</p></div></div></div>}

        {error && <p className="error" role="alert">ERROR:: {error}</p>}
      </div></section>
      <SiteFooter />
    </main>
  );
}
