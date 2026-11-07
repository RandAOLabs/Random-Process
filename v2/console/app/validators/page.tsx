import type { Metadata } from "next";
import { SiteFooter, SiteHeader } from "../../components/site-header";
import { ValidatorGuide } from "../../components/validator-guide";

export const metadata: Metadata = {
  title: "Become a validator — RNG Labs",
  description: "Bond RNG and run an Any-Honest validator: requirements, steps, earnings and risks.",
};

export default function ValidatorsPage() {
  return (
    <main className="shell">
      <SiteHeader active="validators" />
      <ValidatorGuide />
      <SiteFooter />
    </main>
  );
}
