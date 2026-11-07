// fair-client.ts: the browser side of fair play (docs/PERMISSIONLESS.md, "Fair play")
// and the beacon's one-message pay-and-request shape.
//
// The game authorizes each session for the player's key first: the game itself
// sends `Fair.Open { Session, Player }` to the fair process (e.g. when it
// charges the entry), so nobody can make the fair process pay the beacon for a
// game that did not ask. The player's browser draws a secret s, commits H(s)
// to the fair process with a throwaway RSA key (kept in IndexedDB, D13),
// waits until its session is
// `reveal-due` (the beacon value is bound) and only then reveals s. The hashes
// below must match lib/fair.lua byte for byte (vectors: test/run-fair-tests.mjs).
//
// No imports and only erasable TypeScript, so Node runs this file directly
// (tests/console.test.mjs, examples/fair-demo/play.mjs).

const encoder = new TextEncoder();

// ---------------------------------------------------------------- hashes

export async function sha256Hex(text: string | Uint8Array) {
  const bytes = typeof text === "string" ? encoder.encode(text) : text;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes as BufferSource));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

export const commitHash = (game: string, session: string, secret: string) =>
  sha256Hex(`rng/fair/v1/commit|${game}|${session}|${secret}`);
export const sessionValue = (beaconValue: string, game: string, session: string) =>
  sha256Hex(`rng/fair/v1/beacon|${beaconValue}|${game}|${session}`);
export const finalValue = (v: string, secret: string) => sha256Hex(`rng/fair/v1/final|${v}|${secret}`);
export const forfeitValue = (v: string) => sha256Hex(`rng/fair/v1/forfeit|${v}`);
/** The beacon's per-request value (beacon/anyhonest.lua finalize). */
export const requestValue = (roundValue: string, requester: string, requestId: string) =>
  sha256Hex(`hyperbeam/rng/any-honest/v1/request|${roundValue}|${requester}|${requestId}`);

const HEX64 = /^[0-9a-f]{64}$/;
export const isSecret = (s: unknown): s is string => typeof s === "string" && HEX64.test(s);

/** 32 random bytes as 64 lowercase hex characters. */
export function newSecret() {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), (b) => b.toString(16).padStart(2, "0")).join("");
}

// ---------------------------------------------------------------- message shapes

/** Sent by the GAME (its wallet or process) to the fair process: lets key `player` commit to `session`. */
export const fairOpenTags = (session: string, player: string) =>
  ({ Action: "Fair.Open", Session: session, Player: player });
export const fairCommitTags = (game: string, session: string, commit: string, now: number) =>
  ({ Action: "Fair.Commit", Game: game, Session: session, Commit: commit, "Commit-Time": String(Math.floor(now)) });
export const fairRevealTags = (game: string, session: string, secret: string, player: string) =>
  ({ Action: "Fair.Reveal", Game: game, Session: session, Secret: secret, Player: player });
export const fairExpireTags = (game: string, session: string, player: string) =>
  ({ Action: "Fair.Expire", Game: game, Session: session, Player: player });

/**
 * Pay and request in one message: a token Transfer to the beacon. Its
 * Credit-Notice credits the sender and runs Request-Random in the same slot.
 * Send it to the beacon's token, signed by the requester.
 */
export function payAndRequestTags(beacon: string, quantityAtoms: bigint | number | string, requestId: string, now: number) {
  if (!requestId || requestId.length > 128) throw new Error("requestId must be 1-128 characters");
  return { Action: "Transfer", Recipient: beacon, Quantity: String(quantityAtoms),
    "X-Request-Id": requestId, "X-Request-Time": String(Math.floor(now)) };
}

export type RequestRecord = { round: number; value: string; requests?: Array<{ requester: string; requestId: string; value: string }> };

/** A wallet's request in the published round records, with its value rechecked. */
export async function findRequest(records: RequestRecord[] | undefined, requester: string, requestId: string) {
  for (const record of records ?? []) {
    if (!Array.isArray(record.requests)) continue;
    const hit = record.requests.find((r) => r.requester === requester && r.requestId === requestId);
    if (hit) {
      const expected = await requestValue(record.value, requester, requestId);
      return { round: record.round, roundValue: record.value, value: hit.value, valid: expected === hit.value };
    }
  }
  return null;
}

// ---------------------------------------------------------------- session logic

export type FairStatus = "committed" | "reveal-due" | "revealed" | "forfeit";
export type FairSession = {
  game: string; session: string; player: string; commit: string; status: FairStatus;
  batch?: number; round?: number; requestId?: string; beaconValue?: string; v?: string;
  windowMs?: number; committedAt?: number; revealBy?: number; secret?: string; final?: string; resolvedAt?: number;
};
export type NextStep = "wait" | "reveal" | "expire" | "done" | "forfeit-expected";

/**
 * What to do with a session now. Never reveal before `reveal-due`: a secret
 * shown before the beacon value is bound lets the game pick the outcome.
 * `forfeit-expected`: the session is reveal-due but this browser lost its
 * secret (IndexedDB cleared), so it will end as a forfeit.
 */
export function nextStep(view: FairSession | null | undefined, secret: string | null | undefined, now: number): NextStep {
  if (!view) return "wait";
  if (view.status === "revealed" || view.status === "forfeit") return "done";
  if (view.status !== "reveal-due") return "wait";
  if (view.revealBy !== undefined && now > view.revealBy) return "expire";
  return isSecret(secret) ? "reveal" : "forfeit-expected";
}

/** Recompute everything a published session claims. */
export async function verifySession(view: FairSession, secret?: string | null) {
  const problems: string[] = [];
  const s = view.secret ?? secret ?? undefined;
  if (isSecret(s) && await commitHash(view.game, view.session, s) !== view.commit) problems.push("commit does not match the secret");
  let v: string | undefined;
  if (view.beaconValue) {
    v = await sessionValue(view.beaconValue, view.game, view.session);
    if (view.v !== undefined && view.v !== v) problems.push("session value does not match the beacon value");
  }
  let expected: string | undefined;
  if (v && view.status === "revealed") {
    if (!isSecret(view.secret)) problems.push("revealed without a secret");
    else expected = await finalValue(v, view.secret);
  } else if (v && view.status === "forfeit") {
    expected = await forfeitValue(v);
  }
  if (expected !== undefined && view.final !== expected) problems.push("final does not match");
  return { ok: problems.length === 0, expected, problems };
}

/** The fair process's refusal codes, in words. */
export const FAIR_ERRORS: Record<string, string> = {
  "Not-Bound": "The beacon value is not bound yet; reveal later.",
  "Reveal-Late": "The reveal window has closed; the session ends as a forfeit.",
  "Bad-Secret": "The secret does not match the commit.",
  "Session-Taken": "That session already has a different commit.",
  "Session-Done": "That session has already finished.",
  "Stale-Commit": "The commit time is too far from the process clock.",
  "Fair-Full": "The fair process holds too many open sessions; try again shortly.",
  "Not-Expired": "The reveal window is still open.",
  "Not-Opened": "The game has not opened this session for this player key (or the allowance lapsed).",
  "Game-Full": "The game holds too many open sessions; try again shortly.",
  "Bad-Player": "The player key is not a valid address.",
  "Not-Beacon": "Only the configured beacon can bind a value.",
  "Stale-Result": "That beacon result is not for the outstanding request.",
};

// ---------------------------------------------------------------- ANS-104 with WebCrypto

export type BrowserKey = { privateKey: CryptoKey; owner: string; address: string };

function b64url(bytes: Uint8Array) {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlDecode(text: string) {
  const bin = atob(text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}
function concat(parts: Uint8Array[]) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}
const sha384 = async (b: Uint8Array) => new Uint8Array(await crypto.subtle.digest("SHA-384", b as BufferSource));

async function deepHash(value: Uint8Array | Uint8Array[]): Promise<Uint8Array> {
  if (Array.isArray(value)) {
    let acc = await sha384(encoder.encode(`list${value.length}`));
    for (const chunk of value) acc = await sha384(concat([acc, await deepHash(chunk)]));
    return acc;
  }
  return sha384(concat([await sha384(encoder.encode(`blob${value.length}`)), await sha384(value)]));
}

function zigzag(n: number) {
  let v = n * 2; // n >= 0 here: lengths and counts
  const bytes: number[] = [];
  while (v > 0x7f) { bytes.push((v & 0x7f) | 0x80); v = Math.floor(v / 128); }
  bytes.push(v);
  return Uint8Array.from(bytes);
}
function avroString(s: string) { const b = encoder.encode(s); return concat([zigzag(b.length), b]); }
export function encodeTags(tags: Array<{ name: string; value: string }>) {
  if (tags.length === 0) return new Uint8Array(0);
  return concat([zigzag(tags.length), ...tags.flatMap((t) => [avroString(t.name), avroString(t.value)]), Uint8Array.of(0)]);
}
function u64le(n: number) { const b = new Uint8Array(8); new DataView(b.buffer).setBigUint64(0, BigInt(n), true); return b; }

export type DataItem = { target: string; tags: Record<string, string>; data?: string };

/** The deep hash an ANS-104 type-1 signature signs. */
export async function dataItemDigest(owner: string, item: DataItem) {
  const tags = encodeTags(Object.entries(item.tags).map(([name, value]) => ({ name, value })));
  const target = b64urlDecode(item.target);
  if (target.length !== 32) throw new Error("target must be a 43-character process id");
  return { digest: await deepHash([encoder.encode("dataitem"), encoder.encode("1"), encoder.encode("1"),
    b64urlDecode(owner), target, new Uint8Array(0), tags, encoder.encode(item.data ?? "")]), target, tags };
}

/** What a wallet's signDataItem returns, signed by a browser key (RSA-PSS, SHA-256, salt 32). */
export async function signDataItem(key: BrowserKey, item: DataItem) {
  const { digest, target, tags } = await dataItemDigest(key.owner, item);
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "RSA-PSS", saltLength: 32 }, key.privateKey, digest as BufferSource));
  return concat([Uint8Array.of(1, 0), signature, b64urlDecode(key.owner), Uint8Array.of(1), target, Uint8Array.of(0),
    u64le(Object.keys(item.tags).length), u64le(tags.length), tags, encoder.encode(item.data ?? "")]);
}

export async function addressOf(owner: string) {
  return b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", b64urlDecode(owner) as BufferSource)));
}

/** A throwaway Arweave-style key: RSA-4096, private half not extractable. */
export async function createKey(): Promise<BrowserKey> {
  const pair = await crypto.subtle.generateKey(
    { name: "RSA-PSS", modulusLength: 4096, publicExponent: Uint8Array.of(1, 0, 1), hash: "SHA-256" }, false, ["sign", "verify"]);
  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
  if (!jwk.n) throw new Error("could not read the new key");
  return { privateKey: pair.privateKey, owner: jwk.n, address: await addressOf(jwk.n) };
}

// ---------------------------------------------------------------- storage

/** A commit this browser made, with the secret it must reveal. */
export type SavedSession = { fair: string; game: string; session: string; player: string; secret: string; commit: string; committedAt: number };
export interface FairStore {
  getKey(): Promise<BrowserKey | null>;
  putKey(key: BrowserKey): Promise<void>;
  list(): Promise<SavedSession[]>;
  put(saved: SavedSession): Promise<void>;
  remove(saved: SavedSession): Promise<void>;
}

const savedId = (s: Pick<SavedSession, "fair" | "game" | "session" | "player">) => `${s.fair}|${s.game}|${s.session}|${s.player}`;

export function memoryStore(): FairStore {
  let key: BrowserKey | null = null;
  const sessions = new Map<string, SavedSession>();
  return {
    async getKey() { return key; },
    async putKey(k) { key = k; },
    async list() { return [...sessions.values()]; },
    async put(s) { sessions.set(savedId(s), s); },
    async remove(s) { sessions.delete(savedId(s)); },
  };
}

/** IndexedDB: the CryptoKey is stored as itself (structured clone), never exported. */
export function indexedDbStore(name = "rng-fair"): FairStore {
  const open = () => new Promise<IDBDatabase>((resolve, reject) => {
    const req = indexedDB.open(name, 1);
    req.onupgradeneeded = () => { req.result.createObjectStore("keys"); req.result.createObjectStore("sessions"); };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  const run = async <T,>(store: string, mode: IDBTransactionMode, op: (s: IDBObjectStore) => IDBRequest) => {
    const db = await open();
    try {
      return await new Promise<T>((resolve, reject) => {
        const req = op(db.transaction(store, mode).objectStore(store));
        req.onsuccess = () => resolve(req.result as T);
        req.onerror = () => reject(req.error);
      });
    } finally { db.close(); }
  };
  return {
    async getKey() { return (await run<BrowserKey | undefined>("keys", "readonly", (s) => s.get("player"))) ?? null; },
    async putKey(k) { await run("keys", "readwrite", (s) => s.put(k, "player")); },
    async list() { return run<SavedSession[]>("sessions", "readonly", (s) => s.getAll()); },
    async put(saved) { await run("sessions", "readwrite", (s) => s.put(saved, savedId(saved))); },
    async remove(saved) { await run("sessions", "readwrite", (s) => s.delete(savedId(saved))); },
  };
}

// ---------------------------------------------------------------- client

export type FairClientOptions = { fair: string; node?: string; store?: FairStore; fetch?: typeof fetch };

export class FairError extends Error {
  code: string;
  constructor(code: string) { super(FAIR_ERRORS[code] ?? code); this.code = code; }
}

/** The message never got a slot: the node did not schedule it, so it can have no effect. */
export class NotScheduledError extends Error {}

export type FairInfo = { beacon: string; fairWindowMs: number; at: number; protocol: string;
  outstanding?: { batch: number; requestId: string; sentAt: number } | null; requestAfter?: number; minIntervalMs?: number };
export type CommitOptions = { retries?: number; delayMs?: number; sleep?: (ms: number) => Promise<void> };

/** One fair process, driven by this browser's throwaway key. */
export class FairClient {
  fair: string;
  node: string;
  store: FairStore;
  private http: typeof fetch;

  constructor(opts: FairClientOptions) {
    this.fair = opts.fair;
    this.node = (opts.node ?? "/hb-stage").replace(/\/$/, "");
    this.store = opts.store ?? indexedDbStore();
    this.http = opts.fetch ?? ((input, init) => fetch(input, init));
  }

  async key() {
    const saved = await this.store.getKey();
    if (saved) return saved;
    const key = await createKey();
    await this.store.putKey(key);
    return key;
  }

  /** Schedule, push and read one signed message, as lib/wallet.ts does for Wander. */
  async send(tags: Record<string, string>) {
    const base = `${this.node}/${this.fair}~process@1.0`;
    let scheduled: Response;
    try {
      const signed = await signDataItem(await this.key(), { target: this.fair, tags });
      scheduled = await this.http(`${base}/schedule?codec-device=ans104@1.0`, {
        method: "POST", headers: { "content-type": "application/ans104", "accept-bundle": "true" }, body: signed as BodyInit });
    } catch (error) { throw new NotScheduledError(error instanceof Error ? error.message : String(error)); }
    if (!scheduled.ok) throw new NotScheduledError(`The node refused the message (${scheduled.status}).`);
    const slot = Number(scheduled.headers.get("slot"));
    if (!Number.isSafeInteger(slot) || slot < 0) throw new NotScheduledError("The node did not return a valid slot.");
    // From here on the message is in the schedule: a later failure does not undo it.
    const pushed = await this.http(`${base}/push&slot=${slot}`);
    if (!pushed.ok) throw new Error(`The node could not deliver the message (${pushed.status}).`);
    const result = await this.http(`${base}/compute&slot=${slot}/results/output/data`);
    if (!result.ok) throw new Error(`The node could not read the result (${result.status}).`);
    const reply = JSON.parse(await result.text()) as Record<string, unknown>;
    if (typeof reply.error === "string") throw new FairError(reply.error);
    return reply;
  }

  private async read<T>(key: string) {
    const response = await this.http(`${this.node}/${this.fair}~process@1.0/now/${key}`, { cache: "no-store", headers: { accept: "application/ao" } });
    if (!response.ok) throw new Error(`HyperBEAM returned HTTP ${response.status}`);
    return response.json() as Promise<T>;
  }

  info() { return this.read<FairInfo>("fairinfo"); }

  async sessions(game: string) {
    const all = await this.read<Record<string, FairSession[]>>("fairsessions");
    return Array.isArray(all?.[game]) ? all[game] : [];
  }

  /** The address the game must open sessions for (`fairOpenTags(session, player)`). */
  async player() { return (await this.key()).address; }

  /**
   * Step 1, after the game sent Fair.Open for this key. The secret is saved
   * before the commit is sent, so a reload can still reveal. A `Not-Opened`
   * refusal is retried (the game's Fair.Open may still be on its way). The
   * secret is dropped only when the commit surely had no effect: it was never
   * scheduled, or the process refused it.
   */
  async commit(game: string, session: string, opts: CommitOptions = {}) {
    const key = await this.key();
    const secret = newSecret();
    const commit = await commitHash(game, session, secret);
    const saved: SavedSession = { fair: this.fair, game, session, player: key.address, secret, commit, committedAt: Date.now() };
    await this.store.put(saved);
    const retries = opts.retries ?? 5, delayMs = opts.delayMs ?? 2000;
    const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
    for (let attempt = 0; ; attempt++) {
      try { await this.send(fairCommitTags(game, session, commit, saved.committedAt)); return saved; }
      catch (error) {
        if (error instanceof FairError && error.code === "Not-Opened" && attempt < retries) { await sleep(delayMs); continue; }
        if (error instanceof NotScheduledError || error instanceof FairError) await this.store.remove(saved);
        throw error;
      }
    }
  }

  /** Advance one saved session: reveal once it is reveal-due, expire it once late. */
  async step(saved: SavedSession) {
    const view = (await this.sessions(saved.game)).find((s) => s.session === saved.session && s.player === saved.player) ?? null;
    const step = nextStep(view, saved.secret, Date.now());
    // Committed but no request out: the next one may be waiting for the
    // process's minimum interval, which only a message can trigger.
    if (step === "wait" && view?.status === "committed") {
      const info = await this.info();
      if (!info.outstanding && Date.now() >= (info.requestAfter ?? 0)) await this.send({ Action: "Get-Info" });
    }
    if (step === "reveal") await this.send(fairRevealTags(saved.game, saved.session, saved.secret, saved.player));
    if (step === "expire") await this.send(fairExpireTags(saved.game, saved.session, saved.player));
    if (step === "done" && view) {
      const check = await verifySession(view, saved.secret);
      await this.store.remove(saved);
      return { step, view, check };
    }
    return { step, view, check: null };
  }

  /** Every saved session of this fair process, e.g. after a reload. */
  async pending() { return (await this.store.list()).filter((s) => s.fair === this.fair); }
}
