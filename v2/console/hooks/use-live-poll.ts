import { useEffect, useRef } from "react";

// Runs `tick` immediately, then again `gapMs` after each call settles. With
// `lanes` > 1, that many staggered loops run so a slow endpoint is still
// sampled more often than its latency. Pauses while the tab is hidden.
export function useLivePoll(tick: () => Promise<unknown>, gapMs = 1_000, lanes = 1, staggerMs = 0) {
  const ref = useRef(tick);
  useEffect(() => { ref.current = tick; });

  useEffect(() => {
    let stopped = false;
    let running = 0;
    const timers = new Set<number>();
    const wait = (ms: number) => new Promise((resolve) => {
      const id = window.setTimeout(() => { timers.delete(id); resolve(undefined); }, ms);
      timers.add(id);
    });
    const loop = async (delay: number) => {
      running += 1;
      if (delay) await wait(delay);
      while (!stopped && !document.hidden) {
        try { await ref.current(); } catch { /* callers surface their own errors */ }
        if (stopped || document.hidden) break;
        await wait(gapMs);
      }
      running -= 1;
    };
    const start = () => { for (let i = 0; i < lanes; i += 1) void loop(i * staggerMs); };
    const onVisible = () => { if (!document.hidden && running === 0) start(); };
    start();
    document.addEventListener("visibilitychange", onVisible);
    return () => { stopped = true; timers.forEach((id) => window.clearTimeout(id)); document.removeEventListener("visibilitychange", onVisible); };
  }, [gapMs, lanes, staggerMs]);
}
