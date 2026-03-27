const config = {
  stripeLink: "https://buy.stripe.com/test_placeholder",
  downloadLink: "https://downloads.slickshot.app/SlickShot.zip",
};

document.querySelectorAll("[data-stripe-link]").forEach((link) => {
  link.setAttribute("href", config.stripeLink);
  link.addEventListener("click", (event) => {
    if (config.stripeLink.includes("test_placeholder")) {
      event.preventDefault();
      window.alert("Stripe Payment Link を差し替えると購入導線が有効になります。");
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
