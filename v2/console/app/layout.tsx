import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "RNG Labs — HyperBEAM RNG",
  description:
    "Live, publicly verifiable randomness for AO processes on HyperBEAM.",
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
      <body>{children}</body>
    </html>
  );
}
