import { useEffect, useRef } from "react";

// Runs `tick` immediately, then again `gapMs` after each call settles, so
// requests never overlap. Pauses while the tab is hidden.
export function useLivePoll(tick: () => Promise<unknown>, gapMs = 1_000) {
  const ref = useRef(tick);
  useEffect(() => { ref.current = tick; });

  useEffect(() => {
    let stopped = false;
    let active = false;
    let timer: number | undefined;
    const loop = async () => {
      active = true;
      while (!stopped && !document.hidden) {
        try { await ref.current(); } catch { /* callers surface their own errors */ }
        if (stopped || document.hidden) break;
        await new Promise((resolve) => { timer = window.setTimeout(resolve, gapMs); });
      }
      active = false;
    };
    const onVisible = () => { if (!document.hidden && !active) void loop(); };
    void loop();
    document.addEventListener("visibilitychange", onVisible);
    return () => { stopped = true; window.clearTimeout(timer); document.removeEventListener("visibilitychange", onVisible); };
  }, [gapMs]);
}
