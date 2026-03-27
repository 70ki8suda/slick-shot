document.querySelectorAll("[data-stripe-link]").forEach((link) => {
  link.addEventListener("click", (event) => {
    const href = link.getAttribute("href") || "";
    if (href.includes("test_placeholder")) {
      event.preventDefault();
      window.alert("Stripe Payment Link を差し替えると購入導線が有効になります。");
    }
  });
});
