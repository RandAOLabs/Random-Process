/**
 * slot-settle.mjs — wait for the computed head to reach a slot before reading it.
 *
 * ## The one rule this file exists to enforce
 *
 * A HyperBEAM slot carries two things forward and they travel by different
 * routes: the published map goes through the **message cache**, and the Luerl
 * VM — every global the contract keeps its world in — goes through the
 * message's **`priv`**, which is not cached. A `compute&slot=N` asked for
 * before anything has driven the head past N is served off a path with no live
 * worker behind it: `dev_lua` re-enters `init`, runs the module from the top,
 * and calls the handler with a COMPLETE `base` and an EMPTY set of globals.
 *
 * Nothing errors. `users` still reads 50, every `player-<address>` still holds
 * the record it held, and `Players` is empty — so the next wallet to act is
 * minted from nothing, its Rune and Gold are gone, its `joinedAt` is rewritten
 * to now, and a wallet that was already sworn joins a faction all over again.
 *
 * Measured on hyperbeam.tylerw.ai, one fresh process per run, the same
 * bootstrap driven both ways, across two different builds of the contract:
 *
 *     settle by `compute&slot=N` immediately after the POST   5 runs, 5 wiped
 *     settle by the head, then address the slot               3 runs, 0 wiped
 *
 * The two contracts behaved identically in both columns, which is how we know
 * this is the read pattern and not the Lua.
 *
 * ## Why the policy is here and not in either caller
 *
 * There are two transports in this repo that address a slot — the browser and
 * swarm client in `src/lib/hyperbeam.ts`, and the deploy/seed tooling in
 * `backend/native/hbclient.mjs` — and the defect that cost a night was exactly
 * a shape handled in one and not the other. So the POLICY lives here once and
 * each side supplies only its own `readHead`. There is nothing transport- or
 * platform-specific below: no fetch, no timers beyond `setTimeout`, no Node
 * built-ins, so the browser bundle takes it unchanged.
 *
 * ## What it costs
 *
 * One extra round trip in the good case, and less than that in truth: on this
 * node `now/at-slot` is what makes the process COMPUTE to the head, so the work
 * moves under that request rather than being added to it, and the slot read
 * that follows is a cache hit.
 */

/** Sleep that gives up early when the caller has cancelled. */
const wait = (ms, isCancelled) => new Promise((resolve) => {
  if (ms <= 0 || (isCancelled && isCancelled())) { resolve(); return; }
  setTimeout(resolve, ms);
});

/**
 * Poll `readHead` until it reports a computed head at or past `slot`.
 *
 * @param {object} options
 * @param {() => Promise<number | null>} options.readHead reads the process's
 *   computed head, or null when the answer is unavailable. A throw is treated
 *   as unavailable: a node having a moment is ordinary here and is not a reason
 *   to fall through to the racing read.
 * @param {number} options.slot the slot about to be addressed.
 * @param {number} [options.attempts] head reads, including the first.
 * @param {number} [options.delayMs] pause after the first miss.
 * @param {number} [options.maxDelayMs] ceiling on a single pause. Each pause
 *   doubles up to this, so a node that is genuinely behind is not hammered.
 * @param {number} [options.budgetMs] hard wall-clock bound. 0 means none.
 * @param {() => boolean} [options.isCancelled] stop early and return null.
 * @returns {Promise<number | null>} the head it saw, or null if it never got
 *   there. **Null is not a failure to report to a user** — it means the caller
 *   should go ahead and read the slot anyway, because a read that races is
 *   still better than an action that never returns.
 */
export async function settleHead({
  readHead, slot,
  attempts = 40, delayMs = 250, maxDelayMs = 2_000, budgetMs = 30_000,
  isCancelled,
}) {
  const target = Number(slot);
  if (!Number.isSafeInteger(target) || target < 0) return null;
  const tries = Number.isSafeInteger(attempts) && attempts > 0 ? attempts : 1;
  const first = Number.isFinite(delayMs) && delayMs > 0 ? delayMs : 0;
  const cap = Number.isFinite(maxDelayMs) && maxDelayMs > 0
    ? Math.max(first, maxDelayMs) : first;
  const deadline = Number.isFinite(budgetMs) && budgetMs > 0
    ? Date.now() + budgetMs : Number.POSITIVE_INFINITY;

  let pause = first;
  for (let i = 0; i < tries; i += 1) {
    if (isCancelled && isCancelled()) return null;
    let at = null;
    try {
      at = await readHead();
    } catch { at = null; }
    if (at !== null && at !== undefined && Number.isSafeInteger(at) && at >= target) return at;
    const left = deadline - Date.now();
    if (left <= 0 || i + 1 >= tries) break;
    await wait(Math.min(pause, left), isCancelled);
    pause = cap > 0 ? Math.min(cap, Math.max(1, pause) * 2) : 0;
  }
  return null;
}

/**
 * Whether settling is worth paying for against a given process, learned.
 *
 * The head advances by itself only while the process has a live worker, and
 * whether that happens for a given client's writes is a property of the NODE,
 * not of anything a caller can know in advance. Measured on
 * hyperbeam.tylerw.ai: the deploy tooling's httpsig-scheduled writes advance
 * the head in ~350 ms; the app's ANS-104 items did not advance it in 25 s.
 *
 * So the probe is not a fixed tax. The first action against a process pays it;
 * after that, a process whose head has never once arrived on its own is marked
 * and skipped, and re-probed occasionally so the answer can change under us —
 * a node reconfigured, or a worker that has since come up. A process whose head
 * does arrive keeps paying the one round trip, which is what buys the safety.
 *
 * Keyed by node and process, and deliberately in-memory: this is a running
 * observation about a live worker, not a fact to persist anywhere.
 */
const observed = new Map();
/** Re-probe roughly this often after deciding a process's head does not move. */
const REPROBE_EVERY = 16;

/** `settleHead`, but free against a process that has never once settled. */
export async function settleHeadIfUseful(key, options) {
  const seen = observed.get(key) || { advances: null, skipped: 0 };
  if (seen.advances === false && seen.skipped < REPROBE_EVERY) {
    seen.skipped += 1;
    observed.set(key, seen);
    return null;
  }
  const at = await settleHead(options);
  observed.set(key, { advances: at !== null, skipped: 0 });
  return at;
}

/** Forget what has been learned. For tests, and for a node switch. */
export function resetSettleObservations() { observed.clear(); }

export default settleHead;
