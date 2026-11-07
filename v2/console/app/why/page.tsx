import { SiteFooter, SiteHeader } from "../../components/site-header";

const failures = [
  ["01", "NODES DISAGREE", "Runtime seeds and clocks produce different state on every replay."],
  ["02", "SENDERS GRIND", "A predictable local result can be retried until the sender likes it."],
  ["03", "COMMITTEES LEAK", "A known round is useless if requests can still bind themselves to it."],
];

const surfaces = [
  ["LOCAL", "Replay-safe; sender-predictable."],
  ["FAST", "On-demand 2-of-3 threshold BLS; safe unless 2 of 3 operators collude."],
  ["BEACON", "Shared public rounds; free to read."],
  ["ANY-HONEST", "Live time-lock fairness with native proofs."],
  ["PROOF", "Independent retained-round checks."],
];

export default function WhyPage() {
  return (
    <main className="shell compact-page">
      <SiteHeader active="why" />
      <section className="page-titlebar container"><div><p className="kicker">[ 01 // WHY ]</p><h1>Random is not automatically fair.</h1></div><p>A blockchain must replay exactly and resist whoever benefits from predicting the result.</p></section>
      <section className="why-board container">
        <div className="why-failures"><p className="board-label">FAILURE_MODES</p>{failures.map(([index, title, body]) => <article key={index}><span>{index}</span><div><h2>{title}</h2><p>{body}</p></div></article>)}</div>
        <div className="why-contract"><p className="board-label">RNG_SURFACES</p><div className="surface-ledger">{surfaces.map(([name, body]) => <div key={name}><b>{name}</b><span>{body}</span></div>)}</div><p className="trust-line"><b>THE RULE:</b> commit before reveal; verify after publication.</p></div>
      </section>
      <SiteFooter />
    </main>
  );
}
