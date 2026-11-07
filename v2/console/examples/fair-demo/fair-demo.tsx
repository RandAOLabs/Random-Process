"use client";

// Fair-play demo: a player's browser as the honest actor (docs/PERMISSIONLESS.md).
// Mount it on any console page, e.g. app/fair/page.tsx:
//   <FairDemo fair="<fair process id>" game="<game process id>" authorize={askTheGame} />
// `authorize(session, player)` asks YOUR game to open the session for this
// browser's key (the game charges the entry and sends
// `fairOpenTags(session, player)` to the fair process); the commit is only
// accepted after that.
// Typecheck: npx tsc --noEmit -p examples/fair-demo
//
// The browser commits H(secret) with a throwaway key kept in IndexedDB, waits
// until the session is reveal-due and only then reveals. After a reload it
// picks up its saved sessions. If IndexedDB was cleared, the secret is gone
// and the session is shown as a forfeit once its reveal window passes.

import { useEffect, useRef, useState } from "react";
import { FairClient, FairError, fairExpireTags, nextStep, verifySession, type FairSession, type SavedSession } from "../../lib/fair-client";

type Row = { session: FairSession; mine: boolean; local: SavedSession | null; step: string; check?: string };

export type Authorize = (session: string, player: string) => Promise<void>;

export function FairDemo({ fair, game, node, authorize }: { fair: string; game: string; node?: string; authorize: Authorize }) {
  const client = useRef<FairClient | null>(null);
  const [player, setPlayer] = useState("");
  const [rows, setRows] = useState<Row[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const c = new FairClient({ fair, node });
    client.current = c;
    let stopped = false;
    const tick = async () => {
      try {
        const key = await c.key();
        setPlayer(key.address);
        // Advance what this browser committed: reveal once due, expire once late.
        for (const saved of await c.pending()) await c.step(saved).catch((e) => setError(e instanceof Error ? e.message : String(e)));
        const local = await c.pending();
        const now = Date.now();
        const sessions = await c.sessions(game);
        // Anyone may end a late session; this is how a lost secret shows up as a forfeit.
        for (const s of sessions) {
          if (nextStep(s, null, now) === "expire") await c.send(fairExpireTags(s.game, s.session, s.player)).catch(() => undefined);
        }
        setRows(await Promise.all(sessions.slice(-20).reverse().map(async (s) => {
          const mine = s.player === key.address;
          const saved = local.find((l) => l.session === s.session && l.player === s.player) ?? null;
          const step = mine || s.status !== "reveal-due" ? nextStep(s, saved?.secret, now) : "wait";
          const check = s.status === "revealed" || s.status === "forfeit" ? ((await verifySession(s)).ok ? "verified" : "mismatch") : undefined;
          return { session: s, mine, local: saved, step, check };
        })));
      } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
      if (!stopped) window.setTimeout(tick, 2000);
    };
    void tick();
    return () => { stopped = true; };
  }, [fair, game, node]);

  const play = async () => {
    if (!client.current) return;
    setBusy(true); setError("");
    try {
      const session = `demo-${Date.now()}`;
      await authorize(session, await client.current.player());
      await client.current.commit(game, session);
    }
    catch (e) { setError(e instanceof FairError ? `${e.code}: ${e.message}` : e instanceof Error ? e.message : String(e)); }
    finally { setBusy(false); }
  };

  const label = (r: Row) => {
    const s = r.session;
    if (s.status === "revealed") return `Revealed: ${s.final} (${r.check})`;
    if (s.status === "forfeit") return `Forfeit: ${s.final} (${r.check})`;
    if (s.status === "committed") return "Committed, waiting for the beacon value";
    if (r.mine && r.step === "forfeit-expected") return "Secret lost on this device: this session will end as a forfeit";
    return `Reveal due by ${new Date(s.revealBy ?? 0).toLocaleTimeString()}`;
  };

  return (
    <section className="space-y-3 text-[14px] text-[var(--gray)]">
      <p className="m-0">Player key: <code>{player || "creating…"}</code></p>
      <button className="button invert" onClick={() => void play()} disabled={busy || !player}>{busy ? "Committing…" : "Play a fair round"}</button>
      {error && <p className="error" role="alert">{error}</p>}
      <ul className="m-0 list-none space-y-2 p-0">{rows.map((r) => (
        <li key={`${r.session.session}|${r.session.player}`} className="border border-[var(--line)] p-3">
          <p className="m-0 text-[var(--white)]">{r.session.session}{r.mine ? " (you)" : ""}</p>
          <p className="m-0 break-all text-[12px]">{label(r)}</p>
        </li>))}</ul>
    </section>
  );
}
