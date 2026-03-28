export const config = {
  stripeLink: "https://buy.stripe.com/test_5kQ28r6Ed3Rd1rk1ZY5sA00",
  refundEmail: "telekinesick@gmail.com",
  supportEmail: "telekinesick@gmail.com",
};

function setText(target, value) {
  if (target) {
    target.textContent = value;
  }
}

function setHref(target, value) {
  if (target instanceof HTMLAnchorElement) {
    target.href = value;
  }
}

function createRuntimeConfig(win) {
  return {
    location: win.location,
    fetch: win.fetch.bind(win),
    alert: win.alert.bind(win),
    addEventListener: win.addEventListener.bind(win),
    removeEventListener: win.removeEventListener.bind(win),
    assign: (url) => win.location.assign(url),
  };
}

export function applyStaticConfig(doc = document, win = window, runtimeConfig = config) {
  doc.querySelectorAll("[data-stripe-link]").forEach((link) => {
    if (link instanceof HTMLAnchorElement) {
      link.href = runtimeConfig.stripeLink;
      link.addEventListener("click", (event) => {
        if (runtimeConfig.stripeLink.includes("/test_")) {
          event.preventDefault();
          runtimeConfig.alert("いまは Stripe のテスト決済リンクです。本番公開前に live の Payment Link へ差し替えてください。");
        }
      });
    }
  });

  doc.querySelectorAll("[data-refund-form]").forEach((form) => {
    form.addEventListener("submit", (event) => {
      event.preventDefault();

      const formData = new FormData(form);
      const email = String(formData.get("email") || "").trim();
      const note = String(formData.get("note") || "").trim();

      if (!email) {
        runtimeConfig.alert("購入時のメールアドレスを入力してください。");
        return;
      }

      const subject = encodeURIComponent("SlickShot 返金希望");
      const body = encodeURIComponent(
        [
          "SlickShot の返金を希望します。",
          "",
          `購入時のメールアドレス: ${email}`,
          note ? `メモ: ${note}` : "メモ:",
        ].join("\n")
      );

      win.location.href = `mailto:${runtimeConfig.refundEmail}?subject=${subject}&body=${body}`;
    });
  });
}

export function initHeroVideo(doc = document, runtime = createRuntimeConfig(window)) {
  const heroVideo = doc.querySelector("[data-hero-video]");
  if (!(heroVideo instanceof HTMLVideoElement)) {
    return;
  }

  heroVideo.volume = 0.7;

  const enableHeroAudio = async () => {
    cleanupAudioListeners();

    try {
      heroVideo.muted = false;
      await heroVideo.play();
    } catch {
      heroVideo.muted = true;
    }
  };

  const audioGestureEvents = ["pointerdown", "keydown", "touchstart", "wheel"];

  const cleanupAudioListeners = () => {
    audioGestureEvents.forEach((eventName) => {
      runtime.removeEventListener(eventName, enableHeroAudio);
    });
  };

  audioGestureEvents.forEach((eventName) => {
    runtime.addEventListener(eventName, enableHeroAudio, { once: true, passive: true });
  });
}

export async function initThanksPage(doc = document, runtime = createRuntimeConfig(window)) {
  const page = doc.querySelector("[data-page='thanks']");
  if (!page) return;

  const status = doc.querySelector("[data-thanks-status]");
  const downloadLink = doc.querySelector("[data-thanks-download]");
  const supportLink = doc.querySelector("[data-thanks-support]");
  const sessionId = runtime.location.searchParams.get("session_id")?.trim() ?? "";

  setHref(supportLink, `mailto:${config.supportEmail}`);

  if (!sessionId) {
    setText(status, "購入確認に必要な session_id が見つかりませんでした。時間をおいて再度お試しください。");
    if (downloadLink instanceof HTMLElement) downloadLink.hidden = true;
    return;
  }

  setText(status, "支払いを確認しています...");

  try {
    const response = await runtime.fetch("/api/checkout/confirm", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: sessionId }),
    });
    const body = await response.json();

    if (!response.ok || !body.ok) {
      throw new Error(body.error || "confirm-failed");
    }

    setText(status, "ダウンロード準備ができました。再ダウンロード用リンクもメールで送信しています。");
    setHref(downloadLink, body.download_url);
    if (downloadLink instanceof HTMLElement) downloadLink.hidden = false;
  } catch {
    setText(status, "購入確認に失敗しました。時間をおいて再度お試しいただくか、サポートへご連絡ください。");
    if (downloadLink instanceof HTMLElement) downloadLink.hidden = true;
  }
}

export async function initDownloadPage(doc = document, runtime = createRuntimeConfig(window)) {
  const page = doc.querySelector("[data-page='download']");
  if (!page) return;

  const status = doc.querySelector("[data-download-status]");
  const retryForm = doc.querySelector("[data-redownload-form]");
  const supportLink = doc.querySelector("[data-download-support]");
  const token = runtime.location.searchParams.get("token")?.trim() ?? "";

  setHref(supportLink, `mailto:${config.supportEmail}`);

  if (!token) {
    setText(status, "メールのリンクからダウンロードページを開くか、再送フォームをご利用ください。");
    if (retryForm instanceof HTMLElement) retryForm.hidden = false;
    return;
  }

  setText(status, "ダウンロードリンクを確認しています...");

  try {
    const response = await runtime.fetch("/api/download/resolve", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
    });
    const body = await response.json();

    if (!response.ok || !body.ok) {
      throw new Error(body.error || "download-resolve-failed");
    }

    setText(status, "ダウンロードを開始します...");
    runtime.assign(body.signed_url);
  } catch {
    setText(status, "リンクの有効期限が切れているか無効です。再送フォームから新しいリンクを受け取れます。");
    if (retryForm instanceof HTMLElement) retryForm.hidden = false;
  }
}

export function initRedownloadRequestForm(doc = document, runtime = createRuntimeConfig(window)) {
  const form = doc.querySelector("[data-redownload-form]");
  const status = doc.querySelector("[data-redownload-status]");
  if (!(form instanceof HTMLFormElement)) {
    return;
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const formData = new FormData(form);
    const email = String(formData.get("email") || "").trim();

    if (!email) {
      runtime.alert("購入時のメールアドレスを入力してください。");
      return;
    }

    setText(status, "メールを送信しています...");

    try {
      const response = await runtime.fetch("/api/redownload/request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const body = await response.json();

      if (!response.ok || !body.ok) {
        throw new Error(body.error || "redownload-request-failed");
      }

      setText(status, "再ダウンロード用リンクをメールで送信しました。");
    } catch {
      setText(status, "再送に失敗しました。時間をおいて再度お試しいただくか、サポートへご連絡ください。");
    }
  });
}

export async function initPage(doc = document, runtime = createRuntimeConfig(window)) {
  applyStaticConfig(doc, window, config);
  initHeroVideo(doc, runtime);
  initRedownloadRequestForm(doc, runtime);
  await initThanksPage(doc, runtime);
  await initDownloadPage(doc, runtime);
}

if (typeof window !== "undefined" && typeof document !== "undefined") {
  void initPage();
}
