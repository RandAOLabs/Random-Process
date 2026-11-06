"use client";

type ArweaveWallet = {
  connect(permissions: string[], appInfo?: object): Promise<void>;
  getActiveAddress(): Promise<string>;
  signDataItem(item: { data: string; target: string; tags: { name: string; value: string }[] }): Promise<ArrayBuffer>;
};

declare global { interface Window { arweaveWallet?: ArweaveWallet } }

const PERMISSIONS = ["ACCESS_ADDRESS", "ACCESS_PUBLIC_KEY", "SIGN_TRANSACTION"];
const NODE_PATH = "/hb-stage";

export function hasWallet() {
  return typeof window !== "undefined" && Boolean(window.arweaveWallet);
}

export async function connectWallet() {
  const wallet = window.arweaveWallet;
  if (!wallet) throw new Error("Install Wander, then reload this page.");
  await wallet.connect(PERMISSIONS, { name: "RNG Labs Console" });
  return wallet.getActiveAddress();
}

export async function sendMessage(process: string, tags: Record<string, string>, data = "") {
  const wallet = window.arweaveWallet;
  if (!wallet) throw new Error("Connect a wallet first.");
  const signed = await wallet.signDataItem({
    data,
    target: process,
    tags: Object.entries(tags).map(([name, value]) => ({ name, value })),
  });
  const scheduled = await fetch(`${NODE_PATH}/${process}~process@1.0/schedule?codec-device=ans104@1.0`, {
    method: "POST",
    headers: { "content-type": "application/ans104", "accept-bundle": "true" },
    body: new Uint8Array(signed),
  });
  if (!scheduled.ok) throw new Error(`The node refused the message (${scheduled.status}).`);
  const slot = Number(scheduled.headers.get("slot"));
  if (!Number.isSafeInteger(slot) || slot < 0) throw new Error("The node did not return a valid slot.");
  const pushed = await fetch(`${NODE_PATH}/${process}~process@1.0/push&slot=${slot}`);
  if (!pushed.ok) throw new Error(`The node could not deliver the message (${pushed.status}).`);
  const result = await fetch(`${NODE_PATH}/${process}~process@1.0/compute&slot=${slot}/results/output/data`);
  if (!result.ok) throw new Error(`The node could not read the result (${result.status}).`);
  const text = await result.text();
  let reply: unknown = text;
  try { reply = JSON.parse(text); } catch { /* HyperBEAM may return plain text. */ }
  return { slot, reply: reply as Record<string, unknown> };
}
