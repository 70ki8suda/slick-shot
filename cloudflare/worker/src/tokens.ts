const textEncoder = new TextEncoder();

export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", textEncoder.encode(token));
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export async function createDownloadToken(ttlSeconds: number): Promise<{
  token: string;
  tokenHash: string;
  expiresAt: string;
}> {
  const token = crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
  const tokenHash = await hashToken(token);
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();

  return { token, tokenHash, expiresAt };
}
