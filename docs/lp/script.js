const config = {
  stripeLink: "https://buy.stripe.com/test_5kQ28r6Ed3Rd1rk1ZY5sA00",
  downloadLink: "https://downloads.slick-shot.com/SlickShot.zip",
  refundEmail: "telekinesick@gmail.com",
};

document.querySelectorAll("[data-stripe-link]").forEach((link) => {
  link.setAttribute("href", config.stripeLink);
  link.addEventListener("click", (event) => {
    if (config.stripeLink.includes("/test_")) {
      event.preventDefault();
      window.alert("いまは Stripe のテスト決済リンクです。本番公開前に live の Payment Link へ差し替えてください。");
    }
  });
});

document.querySelectorAll("[data-download-link]").forEach((link) => {
  link.setAttribute("href", config.downloadLink);
  link.addEventListener("click", (event) => {
    if (config.downloadLink.includes("downloads.slick-shot.com")) {
      event.preventDefault();
      window.alert("公開前にダウンロードURLを差し替えてください。");
    }
  });
});

document.querySelectorAll("[data-refund-form]").forEach((form) => {
  form.addEventListener("submit", (event) => {
    event.preventDefault();

    const formData = new FormData(form);
    const email = String(formData.get("email") || "").trim();
    const note = String(formData.get("note") || "").trim();

    if (!email) {
      window.alert("購入時のメールアドレスを入力してください。");
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

    window.location.href = `mailto:${config.refundEmail}?subject=${subject}&body=${body}`;
  });
});
