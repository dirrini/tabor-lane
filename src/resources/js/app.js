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

  const workspaceShell = document.querySelector(".workspace-shell");
  const workspaceMenuToggle = document.querySelector("[data-workspace-menu-toggle]");
  const workspaceMenuClose = document.querySelectorAll("[data-workspace-menu-close]");

  if (workspaceShell && workspaceMenuToggle) {
    const setWorkspaceMenu = (open) => {
      workspaceShell.classList.toggle("menu-open", open);
      workspaceMenuToggle.setAttribute("aria-expanded", String(open));
      document.body.classList.toggle("workspace-menu-open", open);
      if (open) workspaceShell.querySelector("[data-workspace-menu-close]")?.focus();
      else workspaceMenuToggle.focus();
    };

    workspaceMenuToggle.addEventListener("click", () => setWorkspaceMenu(true));
    workspaceMenuClose.forEach((button) => {
      button.addEventListener("click", () => setWorkspaceMenu(false));
    });
    workspaceShell.querySelectorAll(".workspace-sidebar nav a").forEach((link) => {
      link.addEventListener("click", () => setWorkspaceMenu(false));
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && workspaceShell.classList.contains("menu-open")) {
        setWorkspaceMenu(false);
      }
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

  const pendingBilling = document.querySelector("[data-billing-pending]");
  if (pendingBilling) {
    const startedAt = Date.now();
    const pollBilling = async () => {
      try {
        const response = await fetch(pendingBilling.dataset.billingStatusUrl, {
          headers: { Accept: "application/json" },
          cache: "no-store",
        });
        if (response.ok) {
          const billing = await response.json();
          if (billing.plan === "premium") {
            window.location.replace(
              pendingBilling.dataset.billingRefreshUrl || window.location.pathname
            );
            return;
          }
        }
      } catch (error) {
        // A temporary network failure is handled by the next polling attempt.
      }
      if (Date.now() - startedAt < 120000) {
        window.setTimeout(pollBilling, 1000);
      }
    };
    window.setTimeout(pollBilling, 500);
  }

  const workspace = document.querySelector("[data-workspace]");
  if (workspace) {
    const cardForm = workspace.querySelector("[data-card-form]");
    const cardFormToggle = workspace.querySelector("[data-card-form-toggle]");
    const cardFormCancel = workspace.querySelector("[data-card-form-cancel]");
    const toast = workspace.querySelector("[data-board-toast]");
    let draggedCard = null;

    const toggleCardForm = (open) => {
      if (!cardForm) return;
      cardForm.hidden = !open;
      if (open) cardForm.querySelector('input[name="title"]')?.focus();
    };

    cardFormToggle?.addEventListener("click", () => toggleCardForm(true));
    cardFormCancel?.addEventListener("click", () => toggleCardForm(false));

    const showToast = (message) => {
      if (!toast) return;
      toast.textContent = message;
      toast.classList.add("visible");
      window.setTimeout(() => toast.classList.remove("visible"), 2400);
    };

    const updateColumnState = () => {
      workspace.querySelectorAll("[data-column-id]").forEach((column) => {
        const count = column.querySelectorAll("[data-card-id]").length;
        const counter = column.querySelector("[data-card-count]");
        const empty = column.querySelector("[data-column-empty]");
        if (counter) counter.textContent = String(count);
        if (empty) empty.hidden = count > 0;
      });
    };

    workspace.querySelectorAll("[data-card-id]").forEach((card) => {
      card.addEventListener("dragstart", () => {
        draggedCard = card;
        card.classList.add("dragging");
      });
      card.addEventListener("dragend", () => {
        card.classList.remove("dragging");
        workspace.querySelectorAll(".drag-over").forEach((column) => column.classList.remove("drag-over"));
        draggedCard = null;
      });
    });

    workspace.querySelectorAll("[data-column-id]").forEach((column) => {
      column.addEventListener("dragover", (event) => {
        event.preventDefault();
        column.classList.add("drag-over");
      });
      column.addEventListener("dragleave", () => column.classList.remove("drag-over"));
      column.addEventListener("drop", async (event) => {
        event.preventDefault();
        column.classList.remove("drag-over");
        if (!draggedCard || draggedCard.closest("[data-column-id]") === column) return;

        const card = draggedCard;
        const previousList = card.parentElement;
        const targetList = column.querySelector("[data-card-list]");
        targetList.appendChild(card);
        updateColumnState();

        const payload = new URLSearchParams({
          csrfToken: workspace.dataset.csrfToken,
          columnId: column.dataset.columnId,
        });
        try {
          const response = await fetch(`/app/cards/${encodeURIComponent(card.dataset.cardId)}/move`, {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
            body: payload,
          });
          const result = await response.json();
          if (!response.ok || !result.success) throw new Error("Move rejected");
          showToast(workspace.dataset.moveSuccess);
        } catch (error) {
          previousList.appendChild(card);
          updateColumnState();
          showToast(workspace.dataset.moveError);
        }
      });
    });
  }
})();
