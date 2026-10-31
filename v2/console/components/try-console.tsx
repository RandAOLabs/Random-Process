"use client";

import { useEffect, useState } from "react";
import { connectWallet, hasWallet, sendMessage } from "../lib/wallet";
import { SiteFooter, SiteHeader } from "./site-header";

type Mode = "local" | "verify" | "request";
type Status = {
  network: string; beacon: string; token: string; round: number; price: number;
  unit: number; nativeVerification: boolean; groupKey: string; signature: string;
  message: string; value: string; verified: boolean;
  tokenInfo: { faucetAmount: number };
};
type Account = { address: string; tokenBalance: number; beaconBalance: number; price: number; unit: number };
type Draw = { requestId: string; round: number; value?: string; verified?: boolean };

const modes: Array<{ key: Mode; command: string; title: string; line: string; price: string; speed: string; trust: string }> = [
  { key: "local", command: "rng derive", title: "LOCAL", line: "Replay-stable bytes from your own seed.", price: "FREE", speed: "IMMEDIATE", trust: "SENDER CAN PREDICT" },
  { key: "verify", command: "rng verify", title: "VERIFY", line: "Inspect the latest threshold round.", price: "FREE", speed: "IMMEDIATE", trust: "2/3 BLS PROOF" },
  { key: "request", command: "rng request", title: "REQUEST", line: "Create a fresh native-verified round.", price: "3 TEST-RNG", speed: "~1 SECOND", trust: "2/3 + ~rng@1.0" },
];

export function TryConsole() {
  const [mode, setMode] = useState<Mode>("verify");
  const [status, setStatus] = useState<Status | null>(null);
  const [statusError, setStatusError] = useState<string | null>(null);
  const [seed, setSeed] = useState("loot-chest-42");
  const [derived, setDerived] = useState("");
  const [deriving, setDeriving] = useState(false);
  const [walletPresent, setWalletPresent] = useState(false);
  const [address, setAddress] = useState<string | null>(null);
  const [account, setAccount] = useState<Account | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [draw, setDraw] = useState<Draw | null>(null);

  async function refreshStatus(round?: number) {
    const response = await fetch(`/api/status${round ? `?round=${round}` : ""}`, { cache: "no-store" });
    const body = await response.json() as Status & { error?: string };
    if (!response.ok) throw new Error(body.error || "status unavailable");
    if (!round) setStatus(body);
    return body;
  }

  useEffect(() => {
    const tick = () => void refreshStatus().then(() => setStatusError(null)).catch((problem) => setStatusError(problem instanceof Error ? problem.message : "status unavailable"));
    const initial = window.setTimeout(tick, 0);
    const timer = window.setInterval(tick, 10_000);
    const wallet = window.setTimeout(() => setWalletPresent(hasWallet()), 0);
    return () => { window.clearTimeout(initial); window.clearTimeout(wallet); window.clearInterval(timer); };
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
  const onFaucet = () => walletAction("REQUESTING_TEST_CREDITS", async () => {
    if (!status) throw new Error("network status is not ready");
    rejectError((await sendMessage(status.token, { Action: "Faucet" })).reply);
    await refreshAccount();
  });
  const onFund = () => walletAction("FUNDING_BEACON", async () => {
    if (!status || !address) throw new Error("connect a wallet first");
    rejectError((await sendMessage(status.token, { Action: "Transfer", Recipient: status.beacon, Quantity: String(status.price * 3 * status.unit), "X-For": address })).reply);
    await refreshAccount();
  });
  const onRequest = () => walletAction("WAITING_FOR_THRESHOLD", async () => {
    if (!status || !address) throw new Error("connect a wallet first");
    const requestId = `console-${Date.now()}-${crypto.randomUUID().slice(0, 8)}`;
    const reply = (await sendMessage(status.beacon, { Action: "Request-Random", Tier: "beacon", "Request-Id": requestId })).reply;
    rejectError(reply);
    const round = Number(reply.round);
    if (!Number.isSafeInteger(round) || round < 1) throw new Error("the beacon did not assign a round");
    setDraw({ requestId, round });
    for (let attempt = 0; attempt < 60; attempt += 1) {
      try {
        const proof = await refreshStatus(round);
        const framed = new TextEncoder().encode(`hyperbeam/rng/v1/request|${proof.value}|${requestId}`);
        const digest = new Uint8Array(
          await crypto.subtle.digest("SHA-256", framed as unknown as BufferSource),
        );
        const value = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
        setDraw({ requestId, round, value, verified: proof.verified });
        await Promise.all([refreshStatus(), refreshAccount()]);
        return;
      } catch { await new Promise((resolve) => window.setTimeout(resolve, 500)); }
    }
    throw new Error(`round ${round} did not finalize within 30 seconds`);
  });

  return (
    <main className="shell">
      <SiteHeader live={Boolean(status?.verified)} network={status?.network} />
      <section className="try-hero container"><p className="kicker">[ INTERACTIVE_TESTNET ]</p><h1>Choose your command.</h1><p className="lede">Three ways to touch the same primitive. No obsolete tiers. No hidden trust assumptions.</p><pre className="try-ascii">{`$ rng try --mode <local|verify|request>\n> protocol: hyperbeam/rng/v1\n> device:   ~rng@1.0\n> network:  ${status?.network ?? "connecting"}`}</pre></section>

      <section className="container mode-grid" aria-label="Try modes">{modes.map((item, index) => <button key={item.key} className={mode === item.key ? "mode-card selected" : "mode-card"} onClick={() => { setMode(item.key); setError(null); }}><span className="mode-index">0{index + 1}</span><code>$ {item.command}</code><h2>{item.title}</h2><p>{item.line}</p><dl><div><dt>PRICE</dt><dd>{item.price}</dd></div><div><dt>SPEED</dt><dd>{item.speed}</dd></div><div><dt>PROOF</dt><dd>{item.trust}</dd></div></dl></button>)}</section>

      <section className="section container"><div className="mode-workbench">
        {mode === "local" && <div className="workbench-grid"><div><p className="kicker">[ MODE::LOCAL ]</p><h2>Derive deterministic bytes.</h2><p className="muted">Length-framed SHA-256 blocks. Same seed, counter and byte count; same output on every replay.</p><label className="field"><span>SEED</span><input value={seed} onChange={(event) => setSeed(event.target.value)} maxLength={4096} /></label><button className="button invert" onClick={derive} disabled={deriving || !seed}>{deriving ? "DERIVING..." : "$ rng derive"}</button></div><div className="terminal"><div className="terminal-bar"><span>stdout</span><span>LOCAL</span></div><div className="terminal-body"><p><span className="prompt">&gt;</span> bytes=32 counter=0</p><code className="big-output">{derived || "waiting_for_input"}</code></div></div></div>}

        {mode === "verify" && <div className="workbench-grid"><div><p className="kicker">[ MODE::VERIFY ]</p><h2>Challenge the latest round.</h2><p className="muted">The console checks the signature against the group key and recomputes the round value locally.</p><button className="button invert" onClick={() => void refreshStatus().catch((problem) => setStatusError(problem instanceof Error ? problem.message : "status unavailable"))}>$ rng verify --latest</button></div><div className="terminal"><div className="terminal-bar"><span>proof.log</span><span>{status?.verified ? "PASS" : "WAIT"}</span></div><div className="terminal-body"><p>round........ {status?.round ?? "—"}</p><p>device....... {status?.nativeVerification ? "~rng@1.0" : "pending"}</p><p>signature.... {status?.signature?.slice(0, 28) ?? "—"}...</p><p>value........ {status?.value ?? "—"}</p><p className={status?.verified ? "pass" : "wait"}>proof......... {status?.verified ? "VERIFIED" : statusError ?? "PENDING"}</p></div></div></div>}

        {mode === "request" && <div><p className="kicker">[ MODE::REQUEST ]</p><h2>Make the committee produce a new value.</h2><p className="muted">Wander signs locally. TEST-RNG has no monetary value. The console never receives your wallet key.</p><ol className="wallet-steps"><li className={address ? "done" : "active"}><span>1</span><div><strong>CONNECT_WANDER</strong><small>{address ?? "authorize this console"}</small></div><button className="button" onClick={onConnect} disabled={Boolean(address) || Boolean(busy)}>{address ? "CONNECTED" : walletPresent ? "CONNECT" : "NO_WALLET"}</button></li><li className={(account?.tokenBalance ?? 0) >= ((status?.price ?? 3) * 3) ? "done" : address ? "active" : ""}><span>2</span><div><strong>GET_TEST_RNG</strong><small>wallet::{account?.tokenBalance ?? "—"}</small></div><button className="button" onClick={onFaucet} disabled={!address || Boolean(busy)}>FAUCET_{status?.tokenInfo.faucetAmount ?? 100}</button></li><li className={(account?.beaconBalance ?? 0) >= (status?.price ?? 3) ? "done" : account ? "active" : ""}><span>3</span><div><strong>FUND_BEACON</strong><small>credit::{account?.beaconBalance ?? "—"}</small></div><button className="button" onClick={onFund} disabled={!account || account.tokenBalance < ((status?.price ?? 3) * 3) || Boolean(busy)}>FUND_{(status?.price ?? 3) * 3}</button></li><li className={(account?.beaconBalance ?? 0) >= (status?.price ?? 3) ? "active" : ""}><span>4</span><div><strong>REQUEST_RANDOM</strong><small>cost::{status?.price ?? 3}_TEST-RNG</small></div><button className="button invert" onClick={onRequest} disabled={!account || account.beaconBalance < (status?.price ?? 3) || Boolean(busy)}>EXECUTE</button></li></ol>{!walletPresent && <p className="notice">WANDER_NOT_FOUND :: <a href="https://wander.app" target="_blank" rel="noreferrer">install wallet</a></p>}{busy && <p className="notice" role="status">{busy} :: approve in Wander if prompted</p>}{draw && <output className="proof-output"><strong>{draw.value ? "RESULT_RECEIVED" : `WAITING_FOR_ROUND_${draw.round}`}</strong>{draw.value && <><span>{draw.verified ? "[ NATIVE_PROOF::PASS ]" : "[ PROOF::UNKNOWN ]"}</span><code>{draw.value}</code><small>round::{draw.round} request::{draw.requestId}</small></>}</output>}</div>}

        {error && <p className="error" role="alert">ERROR:: {error}</p>}
      </div></section>
      <SiteFooter />
    </main>
  );
}
