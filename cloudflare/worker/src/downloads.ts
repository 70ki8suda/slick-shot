import type { Env } from "./env";

const DOWNLOAD_KEY = "SlickShot.zip";

export function createSecureDownloadUrl(env: Pick<Env, "APP_URL">, token: string): string {
  return `${env.APP_URL}/api/download/file?token=${encodeURIComponent(token)}`;
}

export async function streamDownloadFromR2(
  env: Pick<Env, "DOWNLOADS">,
  filename = DOWNLOAD_KEY
): Promise<Response> {
  const object = await env.DOWNLOADS.get(filename);
  if (!object || !object.body) {
    return new Response("Not Found", { status: 404 });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("content-type", object.httpMetadata?.contentType ?? "application/zip");
  headers.set("content-disposition", `attachment; filename="${filename}"`);
  headers.set("cache-control", "private, max-age=60");

  return new Response(object.body, { status: 200, headers });
}
