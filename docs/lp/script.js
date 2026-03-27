const config = {
  stripeLink: "https://buy.stripe.com/test_5kQ28r6Ed3Rd1rk1ZY5sA00",
  downloadLink: "https://downloads.slickshot.app/SlickShot.zip",
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
    if (config.downloadLink.includes("downloads.slickshot.app")) {
      event.preventDefault();
      window.alert("公開前にダウンロードURLを差し替えてください。");
    }
  });
});
