import type { Env } from "./env";

export interface RedownloadEmailInput {
  to: string;
  downloadUrl: string;
}

export async function sendRedownloadEmail(
  env: Pick<Env, "RESEND_API_KEY" | "RESEND_FROM_EMAIL">,
  input: RedownloadEmailInput
): Promise<void> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.RESEND_FROM_EMAIL,
      to: [input.to],
      subject: "SlickShot ダウンロードリンク",
      text: `SlickShot の再ダウンロードはこちら:\n${input.downloadUrl}`,
    }),
  });

  if (!response.ok) {
    throw new Error(`Resend request failed: ${response.status}`);
  }
}
