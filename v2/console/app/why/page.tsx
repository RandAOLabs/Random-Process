import { SiteFooter, SiteHeader } from "../../components/site-header";

export default function WhyPage() {
  return (
    <main className="shell">
      <SiteHeader live network="Native-Testnet" active="why" />
      <section className="content-hero container">
        <p className="kicker">[ 01 // WHY ]</p>
        <h1>Blockchains cannot use ordinary randomness.</h1>
        <p className="lede">A deterministic network must reproduce the same state on every node and every replay. Clocks, runtime seeds and ordinary <code>math.random</code> calls break that rule.</p>
      </section>

      <section className="section container">
        <div className="section-head"><div><p className="kicker">[ THE_PROBLEM ]</p><h2>Random does not mean fair.</h2></div><p>Most random-number APIs were designed for one machine, not an adversarial replicated computer.</p></div>
        <div className="explain-grid">
          <article><span>FAIL_01</span><h3>Nodes can disagree.</h3><p>If each node receives a different runtime seed or clock value, the process forks.</p></article>
          <article><span>FAIL_02</span><h3>The sender can predict.</h3><p>Deterministic local inputs are replay-safe, but a sender can inspect or retry them before committing value.</p></article>
          <article><span>FAIL_03</span><h3>Requests can be ground.</h3><p>If a requester learns a round before its request is locked, it can try IDs until it likes the result.</p></article>
        </div>
      </section>

      <section className="section container split-explanation">
        <div><p className="kicker">[ THE_REQUIREMENT ]</p><h2>Blockchain randomness needs two properties at once.</h2></div>
        <div className="prose"><h3>Deterministic replay</h3><p>Once randomness is published, every node must derive the exact same bytes forever.</p><h3>Unpredictability before commitment</h3><p>When value is at stake, nobody below the committee threshold should know the result before the request set is locked.</p></div>
      </section>

      <section className="section container">
        <div className="section-head"><div><p className="kicker">[ WHAT_RNG_PROVIDES ]</p><h2>One API. Explicit trust.</h2></div><p>Choose the cheapest safe contract for each action instead of pretending every random value has the same guarantees.</p></div>
        <div className="guarantee-list"><div><b>LOCAL</b><span>Immediate and replay-stable, but predictable to the sender.</span></div><div><b>THRESHOLD</b><span>A fast, request-bound 2-of-3 BLS result for value-bearing actions.</span></div><div><b>BEACON</b><span>A shared public round that applications can follow and independently verify.</span></div><div><b>ANY-HONEST</b><span>Time-lock commit/reveal security that remains fair while one validator is honest. Currently being restored to the unified device.</span></div><div><b>PROOF</b><span>Free inspection through HyperBEAM’s native <code>~rng@1.0</code> cryptographic core.</span></div></div>
      </section>

      <section className="section container trust-box"><p className="kicker">[ HONEST_LIMITS ]</p><h2>What it does not promise.</h2><p>Threshold committee collusion can reconstruct rounds early. A committee can censor or stop signing. A funded requester can buy multiple independent draws. The protocol makes these trust boundaries explicit rather than hiding them behind “random.”</p></section>

      <section className="next-page container"><span>NEXT::</span><a href="/how">HOW_THE_PROTOCOL_WORKS →</a></section>
      <SiteFooter />
    </main>
  );
}
