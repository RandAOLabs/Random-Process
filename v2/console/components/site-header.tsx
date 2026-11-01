import Image from "next/image";
import Link from "next/link";

type ActivePage = "why" | "how" | "try";
type Props = { live?: boolean; network?: string; active?: ActivePage };

const navigation: Array<{ key: ActivePage; index: string; label: string; href: string }> = [
  { key: "why", index: "01", label: "WHY", href: "/why" },
  { key: "how", index: "02", label: "HOW", href: "/how" },
  { key: "try", index: "03", label: "TRY", href: "/try" },
];

export function SiteHeader({ live = false, network = "connecting", active }: Props) {
  return (
    <header className="topbar">
      <Link className="brand" href="/" aria-label="RNG Labs home">
        <Image className="brand-logo" src="/rng.png" width={48} height={48} alt="" priority unoptimized />
        <span className="brand-copy"><strong>RNG_LABS</strong><small>CIPHERPLAY::HYPERBEAM</small></span>
      </Link>
      <nav className="nav-rail" aria-label="Main navigation">
        {navigation.map((item) => (
          <Link key={item.key} href={item.href} className={active === item.key ? "active" : undefined} aria-current={active === item.key ? "page" : undefined}>
            <span>{item.index}</span><strong>{item.label}</strong>
          </Link>
        ))}
      </nav>
      <Link className="status-chip" href="/how#live"><span className={live ? "signal on" : "signal"} /><span><strong>~rng@1.0</strong><small>{network}</small></span></Link>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="footer"><strong>RNG_LABS // CIPHERPLAY_INC</strong><span>HYPERBEAM_RNG_V1 :: TESTNET_CANDIDATE</span></footer>
  );
}
