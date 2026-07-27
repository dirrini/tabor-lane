(() => {
  const header = document.querySelector("[data-header]");
  const navToggle = document.querySelector("[data-nav-toggle]");
  const nav = document.querySelector("[data-nav]");

  if (header) {
    const updateHeader = () => header.classList.toggle("scrolled", window.scrollY > 20);
    updateHeader();
    window.addEventListener("scroll", updateHeader, { passive: true });
  }

  if (navToggle && nav) {
    navToggle.addEventListener("click", () => {
      const open = nav.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", String(open));
    });
  }

  const billingToggle = document.querySelector("[data-billing-toggle]");
  const premiumPrice = document.querySelector("[data-monthly][data-yearly]");

  if (billingToggle && premiumPrice) {
    billingToggle.addEventListener("click", (event) => {
      const button = event.target.closest("[data-billing]");
      if (!button) return;

      billingToggle.querySelectorAll("[data-billing]").forEach((item) => {
        item.classList.toggle("active", item === button);
      });

      premiumPrice.textContent =
        button.dataset.billing === "yearly"
          ? premiumPrice.dataset.yearly
          : premiumPrice.dataset.monthly;
    });
  }
})();

