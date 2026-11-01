import Image from "next/image";
import Link from "next/link";

type Props = { live?: boolean; network?: string };

export function SiteHeader({ live = false, network = "connecting" }: Props) {
  return (
    <header className="topbar">
      <Link className="brand" href="/" aria-label="RNG Labs home">
        <Image className="brand-logo" src="/rng.png" width={48} height={48} alt="" priority unoptimized />
        <span className="brand-copy"><strong>RNG_LABS</strong><small>CIPHERPLAY::HYPERBEAM</small></span>
      </Link>
      <nav aria-label="Main navigation">
        <Link href="/why">./why</Link>
        <Link href="/how">./how</Link>
        <Link href="/try">./try</Link>
      </nav>
      <Link className="status-chip" href="/how#live"><span className={live ? "signal on" : "signal"} />{network}</Link>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="footer"><strong>RNG_LABS // CIPHERPLAY_INC</strong><span>HYPERBEAM_RNG_V1 :: TESTNET_CANDIDATE</span></footer>
  );
}
