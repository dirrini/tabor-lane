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
    workspaceShell.querySelector(".workspace-account")?.addEventListener("click", () => {
      setWorkspaceMenu(false);
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

  const initPendingBilling = (root) => {
    const pendingBilling = root.matches?.("[data-billing-pending]")
      ? root
      : root.querySelector?.("[data-billing-pending]");
    if (!pendingBilling || pendingBilling.dataset.billingInitialized) return;
    pendingBilling.dataset.billingInitialized = "true";
    const startedAt = Date.now();
    const pollBilling = async () => {
      if (!pendingBilling.isConnected) return;
      try {
        const response = await fetch(pendingBilling.dataset.billingStatusUrl, {
          headers: { Accept: "application/json" },
          cache: "no-store",
        });
        if (response.ok) {
          const billing = await response.json();
          if (billing.plan === "premium") {
            const refreshUrl =
              pendingBilling.dataset.billingRefreshUrl || window.location.pathname;
            if (window.htmx && document.querySelector("#workspace-main")) {
              window.htmx.ajax("GET", refreshUrl, {
                target: "#workspace-main",
                swap: "outerHTML show:top",
              });
            } else {
              window.location.replace(refreshUrl);
            }
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
  };

  const initWorkspaceBoard = (root) => {
    const workspace = root.matches?.("[data-workspace]")
      ? root
      : root.querySelector?.("[data-workspace]");
    if (!workspace || workspace.dataset.workspaceInitialized) return;
    workspace.dataset.workspaceInitialized = "true";
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
        const wipCounter = column.querySelector("[data-wip-count]");
        const empty = column.querySelector("[data-column-empty]");
        if (counter) counter.textContent = String(count);
        if (wipCounter) wipCounter.textContent = String(count);
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
          const moveSucceeded = result.success ?? result.SUCCESS;
          if (!response.ok || !moveSucceeded) throw new Error("Move rejected");
          showToast(workspace.dataset.moveSuccess);
        } catch (error) {
          previousList.appendChild(card);
          updateColumnState();
          showToast(workspace.dataset.moveError);
        }
      });
    });
  };

  const initCardDetails = (root) => {
    const archiveForm = root.matches?.("[data-card-archive]")
      ? root
      : root.querySelector?.("[data-card-archive]");
    if (!archiveForm || archiveForm.dataset.archiveInitialized) return;
    archiveForm.dataset.archiveInitialized = "true";
    archiveForm.addEventListener("submit", (event) => {
      if (!window.confirm(archiveForm.dataset.confirm)) event.preventDefault();
    });
  };

  const initAttachments = (root) => {
    const attachmentForm = root.matches?.("[data-attachment-form]")
      ? root
      : root.querySelector?.("[data-attachment-form]");
    if (attachmentForm && !attachmentForm.dataset.attachmentInitialized) {
      attachmentForm.dataset.attachmentInitialized = "true";
      attachmentForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        const fileInput = attachmentForm.querySelector('input[type="file"]');
        const submitButton = attachmentForm.querySelector('button[type="submit"]');
        const submitLabel = attachmentForm.querySelector("[data-attachment-submit-label]");
        const status = attachmentForm.querySelector("[data-attachment-status]");
        const file = fileInput?.files?.[0];
        if (!file) return;
        submitButton.disabled = true;
        const originalLabel = submitLabel.textContent;
        submitLabel.textContent = attachmentForm.dataset.uploading;
        status.textContent = "";
        try {
          const csrfToken = document.querySelector("[data-card-csrf-token]")?.dataset.cardCsrfToken;
          const presignBody = new URLSearchParams({
            csrfToken,
            filename: file.name,
            contentType: file.type || "application/octet-stream",
            size: String(file.size),
          });
          const presignResponse = await fetch(attachmentForm.dataset.presignUrl, {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
            body: presignBody,
          });
          const presign = await presignResponse.json();
          const success = presign.success ?? presign.SUCCESS;
          if (!presignResponse.ok || !success) throw new Error(presign.code ?? presign.CODE);
          const attachmentId = presign.id ?? presign.ID;
          const uploadUrl = presign.uploadUrl ?? presign.UPLOADURL;
          const uploadResponse = await fetch(uploadUrl, {
            method: "PUT",
            headers: { "Content-Type": file.type || "application/octet-stream" },
            body: file,
          });
          if (!uploadResponse.ok) throw new Error("upload_failed");
          const completeBody = new URLSearchParams({ csrfToken });
          const completeResponse = await fetch(
            attachmentForm.dataset.completeUrlTemplate.replace("{id}", encodeURIComponent(attachmentId)),
            {
              method: "POST",
              headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
              body: completeBody,
            }
          );
          const completed = await completeResponse.json();
          if (!completeResponse.ok || !(completed.success ?? completed.SUCCESS)) {
            throw new Error(completed.code ?? completed.CODE ?? "upload_failed");
          }
          const refreshUrl = `${window.location.pathname}?attached=1`;
          if (window.htmx) {
            window.htmx.ajax("GET", refreshUrl, {
              target: "#card-attachments",
              select: "#card-attachments",
              swap: "outerHTML",
            });
          } else {
            window.location.assign(refreshUrl);
          }
        } catch (error) {
          const errorKey = String(error.message || "").replaceAll("_", "-");
          status.textContent =
            attachmentForm.dataset[
              `error${errorKey.replace(/(^|-)([a-z])/g, (_, __, letter) => letter.toUpperCase())}`
            ] || attachmentForm.dataset.errorDefault;
        } finally {
          submitButton.disabled = false;
          submitLabel.textContent = originalLabel;
        }
      });
    }
    const scope = root.querySelectorAll ? root : document;
    scope.querySelectorAll("[data-attachment-remove]").forEach((form) => {
      if (form.dataset.removeInitialized) return;
      form.dataset.removeInitialized = "true";
      form.addEventListener("submit", (event) => {
        if (!window.confirm(form.dataset.confirm)) event.preventDefault();
      });
    });
  };

  const updateWorkspaceNavigation = (root) => {
    const workspaceMain = root.matches?.("[data-workspace-page]")
      ? root
      : root.querySelector?.("[data-workspace-page]");
    if (!workspaceMain || !workspaceShell) return;
    const page = workspaceMain.dataset.workspacePage;
    const paths = { app: "/app", members: "/app/members" };

    workspaceShell.querySelectorAll(".workspace-sidebar nav a").forEach((link) => {
      const active = paths[page] && link.getAttribute("href") === paths[page];
      link.classList.toggle("active", Boolean(active));
      if (active) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    });

    const account = workspaceShell.querySelector(".workspace-account");
    const accountActive = page === "profile" || page === "billing";
    account?.classList.toggle("active", accountActive);
    if (accountActive) account?.setAttribute("aria-current", "page");
    else account?.removeAttribute("aria-current");

    document.body.className = `page-${page}`;
  };

  const initDynamicContent = (root) => {
    initPendingBilling(root);
    initWorkspaceBoard(root);
    initCardDetails(root);
    initAttachments(root);
    updateWorkspaceNavigation(root);
  };

  initDynamicContent(document);
  document.body.addEventListener("htmx:load", (event) => {
    initDynamicContent(event.detail.elt);
  });
  document.body.addEventListener("htmx:beforeSwap", (event) => {
    const responseUrl = event.detail.xhr.responseURL;
    if (responseUrl && new URL(responseUrl).pathname === "/login") {
      event.preventDefault();
      window.location.assign(responseUrl);
    }
  });
})();
