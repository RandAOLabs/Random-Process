import type { Metadata } from "next";
import "./globals.css";
import { HealthBanner } from "../components/health-banner";

export const metadata: Metadata = {
  title: "RNG Labs — The randomness library for blockchains",
  description:
    "Deterministic and publicly verifiable randomness for blockchain applications, built on HyperBEAM.",
  icons: {
    icon: "/rng.png",
    shortcut: "/rng.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}<HealthBanner /></body>
    </html>
  );
}
