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
    const viewedLabel = workspace.querySelector("[data-board-viewed-label]");
    const realtimeStatus = workspace.querySelector("[data-board-realtime-status]");
    const realtimeLabel = workspace.querySelector("[data-board-realtime-label]");
    const realtimeEnabled = workspace.dataset.boardRealtimeEnabled === "true";
    const viewedStartedAt = Date.now();
    let draggedCard = null;
    let dragOrigin = null;
    let dropAttempted = false;
    let pollTimer = null;
    let pollController = null;
    let boardRefreshController = null;
    let boardRefreshPending = false;
    let boardCleanedUp = false;
    let pendingBoardWrites = 0;
    let realtimeSource = null;
    let realtimeRestartTimer = null;
    let realtimeConnected = false;
    let realtimeRetryDelay = 1000;

    const toggleCardForm = (open) => {
      if (!cardForm) return;
      cardForm.hidden = !open;
      cardFormToggle?.setAttribute("aria-expanded", String(open));
      if (open) cardForm.querySelector('input[name="title"]')?.focus();
    };

    cardFormToggle?.addEventListener("click", () => toggleCardForm(true));
    cardFormCancel?.addEventListener("click", () => toggleCardForm(false));

    workspace.querySelectorAll("[data-lane-card-create]").forEach((creator) => {
      const toggle = creator.querySelector("[data-lane-card-toggle]");
      const form = creator.querySelector("[data-lane-card-form]");
      const cancel = creator.querySelector("[data-lane-card-cancel]");
      const setOpen = (open) => {
        if (!form) return;
        form.hidden = !open;
        if (toggle) {
          toggle.hidden = open;
          toggle.setAttribute("aria-expanded", String(open));
        }
        if (open) form.querySelector('input[name="title"]')?.focus();
        else form.reset();
      };
      toggle?.addEventListener("click", () => {
        workspace.querySelectorAll("[data-lane-card-form]:not([hidden])").forEach((openForm) => {
          openForm.hidden = true;
          openForm.reset();
          const openCreator = openForm.closest("[data-lane-card-create]");
          const openToggle = openCreator?.querySelector("[data-lane-card-toggle]");
          if (openToggle) {
            openToggle.hidden = false;
            openToggle.setAttribute("aria-expanded", "false");
          }
        });
        setOpen(true);
      });
      cancel?.addEventListener("click", () => setOpen(false));
    });

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
        const wipContainer = column.querySelector("[data-wip-limit]");
        const wipProgress = column.querySelector("[data-wip-progress]");
        if (wipContainer && wipProgress) {
          const limit = Number(wipContainer.dataset.wipLimit);
          const percent = limit > 0 ? Math.min(100, Math.round(count * 100 / limit)) : 0;
          wipProgress.setAttribute("aria-valuenow", String(Math.min(count, limit)));
          wipProgress.setAttribute(
            "aria-valuetext",
            wipContainer.dataset.wipValueTemplate
              .replace("{count}", String(count))
              .replace("{limit}", String(limit)),
          );
          wipProgress.querySelector("i")?.style.setProperty("width", `${percent}%`);
          wipContainer.classList.toggle("is-at-limit", limit > 0 && count >= limit);
          wipContainer.classList.toggle(
            "is-near-limit",
            limit > 0 && count < limit && count * 100 / limit >= 75,
          );
        }
      });
      const progressCards = workspace.querySelectorAll(
        '[data-column-id][data-hidden-from-members="false"] [data-card-id]',
      );
      const total = progressCards.length;
      const completed = [...progressCards].filter(
        (card) => card.dataset.cardCompleted === "true",
      ).length;
      const percent = total > 0 ? Math.round(completed * 100 / total) : 0;
      const totalCounter = workspace.querySelector("[data-board-total-count]");
      const completedCounter = workspace.querySelector("[data-board-completed-count]");
      const progressLabel = workspace.querySelector("[data-board-progress-label]");
      const progress = workspace.querySelector("[data-board-progress]");
      if (totalCounter) totalCounter.textContent = String(total);
      if (completedCounter) completedCounter.textContent = String(completed);
      if (progressLabel) {
        progressLabel.textContent = total === 1
          ? progressLabel.dataset.singular
          : progressLabel.dataset.plural;
      }
      if (progress) {
        progress.setAttribute("aria-valuenow", String(percent));
        progress.querySelector("i")?.style.setProperty("width", `${percent}%`);
      }
    };

    const restoreDraggedCard = () => {
      if (!dragOrigin?.card || !dragOrigin.list?.isConnected) return;
      const nextSibling = dragOrigin.nextSibling?.isConnected ? dragOrigin.nextSibling : null;
      dragOrigin.list.insertBefore(dragOrigin.card, nextSibling);
      updateColumnState();
    };

    const cardBeforePointer = (list, clientX, clientY) => {
      const cards = [...list.querySelectorAll("[data-card-id]:not(.dragging)")];
      if (!cards.length) return null;
      const rows = [];
      cards.forEach((card) => {
        const rect = card.getBoundingClientRect();
        let row = rows.find((candidate) => Math.abs(candidate.top - rect.top) < Math.min(rect.height, 24));
        if (!row) {
          row = { top: rect.top, bottom: rect.bottom, cards: [] };
          rows.push(row);
        }
        row.bottom = Math.max(row.bottom, rect.bottom);
        row.cards.push({ card, rect });
      });
      rows.sort((first, second) => first.top - second.top);
      const targetRowIndex = rows.findIndex((row) => clientY < row.bottom);
      const resolvedRowIndex = targetRowIndex === -1 ? rows.length - 1 : targetRowIndex;
      const targetRow = rows[resolvedRowIndex];
      if (clientY > targetRow.bottom) return null;
      targetRow.cards.sort((first, second) => first.rect.left - second.rect.left);
      return targetRow.cards.find(({ rect }) => clientX < rect.left + rect.width / 2)?.card
        || rows[resolvedRowIndex + 1]?.cards
          .sort((first, second) => first.rect.left - second.rect.left)[0]?.card
        || null;
    };

    workspace.querySelectorAll("[data-card-id]").forEach((card) => {
      card.addEventListener("dragstart", (event) => {
        draggedCard = card;
        dragOrigin = {
          card,
          list: card.parentElement,
          nextSibling: card.nextElementSibling,
        };
        dropAttempted = false;
        card.classList.add("dragging");
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("text/plain", card.dataset.cardId);
      });
      card.addEventListener("dragend", () => {
        card.classList.remove("dragging");
        workspace.querySelectorAll(".drag-over").forEach((column) => column.classList.remove("drag-over"));
        if (!dropAttempted) restoreDraggedCard();
        draggedCard = null;
      });
    });

    workspace.querySelectorAll("[data-column-id]").forEach((column) => {
      column.addEventListener("dragover", (event) => {
        if (!draggedCard || column.classList.contains("is-collapsed")) return;
        event.preventDefault();
        event.dataTransfer.dropEffect = "move";
        column.classList.add("drag-over");
        const targetList = column.querySelector("[data-card-list]");
        const beforeCard = cardBeforePointer(targetList, event.clientX, event.clientY);
        targetList.insertBefore(draggedCard, beforeCard);
        updateColumnState();
      });
      column.addEventListener("dragleave", (event) => {
        if (!column.contains(event.relatedTarget)) column.classList.remove("drag-over");
      });
      column.addEventListener("drop", async (event) => {
        if (!draggedCard || column.classList.contains("is-collapsed")) return;
        event.preventDefault();
        dropAttempted = true;
        column.classList.remove("drag-over");

        const card = draggedCard;
        const targetList = column.querySelector("[data-card-list]");
        const nextCard = card.nextElementSibling?.matches("[data-card-id]")
          ? card.nextElementSibling
          : null;
        updateColumnState();

        const payload = new URLSearchParams({
          csrfToken: workspace.dataset.csrfToken,
          columnId: column.dataset.columnId,
          beforeCardId: nextCard?.dataset.cardId || "",
        });
        pendingBoardWrites += 1;
        try {
          const response = await fetch(`/app/cards/${encodeURIComponent(card.dataset.cardId)}/move`, {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
            body: payload,
          });
          const result = await response.json();
          const moveSucceeded = result.success ?? result.SUCCESS;
          if (!response.ok || !moveSucceeded) throw new Error("Move rejected");
          const completionState = column.dataset.completionState;
          if (completionState !== "preserve") {
            const completed = completionState === "complete";
            card.classList.toggle("is-completed", completed);
            card.dataset.cardCompleted = String(completed);
            const completedLabel = card.querySelector("[data-card-completed-label]");
            if (completedLabel) completedLabel.hidden = !completed;
          }
          const revision = result.revision ?? result.REVISION;
          if (revision) {
            workspace.dataset.boardRevision = revision;
          }
          updateColumnState();
          showToast(workspace.dataset.moveSuccess);
        } catch (error) {
          restoreDraggedCard();
          showToast(workspace.dataset.moveError);
        } finally {
          pendingBoardWrites = Math.max(0, pendingBoardWrites - 1);
          card.classList.remove("dragging");
          dragOrigin = null;
          dropAttempted = false;
        }
      });
    });

    const saveLaneLayout = async (column) => {
      const payload = new URLSearchParams({
        csrfToken: workspace.dataset.csrfToken,
        widthPx: column.dataset.laneWidth,
        isCollapsed: column.dataset.laneCollapsed,
      });
      try {
        const response = await fetch(`/app/lanes/${encodeURIComponent(column.dataset.columnId)}/layout`, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
          body: payload,
        });
        const result = await response.json();
        if (!response.ok || !(result.success ?? result.SUCCESS)) throw new Error("Layout rejected");
        const savedWidth = result.widthPx ?? result.WIDTHPX;
        column.dataset.laneWidth = String(savedWidth);
        column.style.setProperty("--lane-width", `${savedWidth}px`);
        showToast(workspace.dataset.layoutSaved);
      } catch (error) {
        showToast(workspace.dataset.layoutError);
      }
    };

    workspace.querySelectorAll("[data-column-id]").forEach((column) => {
      const collapseButton = column.querySelector("[data-lane-collapse]");
      const resizeHandle = column.querySelector("[data-lane-resize]");
      collapseButton?.addEventListener("click", () => {
        const isCollapsed = column.dataset.laneCollapsed !== "true";
        column.dataset.laneCollapsed = String(isCollapsed);
        column.classList.toggle("is-collapsed", isCollapsed);
        const label = isCollapsed
          ? collapseButton.dataset.expandLabel
          : collapseButton.dataset.collapseLabel;
        collapseButton.setAttribute("aria-label", label);
        collapseButton.title = label;
        const iconUse = collapseButton.querySelector("use");
        iconUse?.setAttribute(
          "href",
          `/resources/icons.svg#${isCollapsed ? "expand-horizontal" : "collapse-horizontal"}`,
        );
        saveLaneLayout(column);
      });

      let resizeState = null;
      const finishResize = (event) => {
        if (!resizeState) return;
        resizeHandle.releasePointerCapture?.(event.pointerId);
        resizeHandle.removeEventListener("pointermove", resizeLane);
        resizeHandle.removeEventListener("pointerup", finishResize);
        resizeHandle.removeEventListener("pointercancel", cancelResize);
        column.classList.remove("is-resizing");
        resizeState = null;
        saveLaneLayout(column);
      };
      const cancelResize = (event) => {
        if (!resizeState) return;
        column.dataset.laneWidth = String(resizeState.startWidth);
        column.style.setProperty("--lane-width", `${resizeState.startWidth}px`);
        finishResize(event);
      };
      const resizeLane = (event) => {
        if (!resizeState) return;
        const width = Math.max(240, Math.min(1200, resizeState.startWidth + event.clientX - resizeState.startX));
        column.dataset.laneWidth = String(Math.round(width));
        column.style.setProperty("--lane-width", `${Math.round(width)}px`);
      };
      resizeHandle?.addEventListener("pointerdown", (event) => {
        if (column.classList.contains("is-collapsed") || event.button !== 0) return;
        event.preventDefault();
        resizeState = {
          startX: event.clientX,
          startWidth: Number(column.dataset.laneWidth) || column.getBoundingClientRect().width,
        };
        column.classList.add("is-resizing");
        resizeHandle.setPointerCapture?.(event.pointerId);
        resizeHandle.addEventListener("pointermove", resizeLane);
        resizeHandle.addEventListener("pointerup", finishResize);
        resizeHandle.addEventListener("pointercancel", cancelResize);
      });
      resizeHandle?.addEventListener("keydown", (event) => {
        if (column.classList.contains("is-collapsed") || !["ArrowLeft", "ArrowRight"].includes(event.key)) return;
        event.preventDefault();
        const increment = event.key === "ArrowRight" ? 40 : -40;
        const width = Math.max(240, Math.min(1200, (Number(column.dataset.laneWidth) || 280) + increment));
        column.dataset.laneWidth = String(width);
        column.style.setProperty("--lane-width", `${width}px`);
        saveLaneLayout(column);
      });
    });

    const updateViewedLabel = () => {
      if (!viewedLabel) return;
      const elapsedMinutes = Math.floor((Date.now() - viewedStartedAt) / 60000);
      if (elapsedMinutes < 1) {
        viewedLabel.textContent = workspace.dataset.viewedNow;
      } else if (elapsedMinutes < 60) {
        viewedLabel.textContent = workspace.dataset.viewedMinutes.replace(
          "{count}",
          String(elapsedMinutes),
        );
      } else {
        viewedLabel.textContent = workspace.dataset.viewedHours.replace(
          "{count}",
          String(Math.floor(elapsedMinutes / 60)),
        );
      }
    };

    const boardIsBusy = () => {
      const activeElement = document.activeElement;
      return Boolean(
        draggedCard
        || pendingBoardWrites > 0
        || workspace.querySelector(".is-resizing")
        || workspace.querySelector("[data-card-form]:not([hidden])")
        || workspace.querySelector("[data-lane-card-form]:not([hidden])")
        || (
          activeElement
          && workspace.contains(activeElement)
          && activeElement.matches("input, textarea, select, [contenteditable='true']")
        )
      );
    };

    const setRealtimeState = (state) => {
      if (!realtimeStatus || !realtimeLabel) return;
      const labels = {
        connecting: workspace.dataset.realtimeConnecting,
        live: workspace.dataset.realtimeConnected,
        reconnecting: workspace.dataset.realtimeReconnecting,
      };
      realtimeStatus.classList.remove("is-connecting", "is-live", "is-reconnecting");
      realtimeStatus.classList.add(`is-${state}`);
      realtimeStatus.dataset.realtimeState = state;
      realtimeLabel.textContent = labels[state] || labels.connecting;
    };

    const stopRealtimeSync = () => {
      window.clearTimeout(realtimeRestartTimer);
      realtimeRestartTimer = null;
      realtimeSource?.close();
      realtimeSource = null;
      realtimeConnected = false;
    };

    const realtimeEventsUrl = () => {
      const url = new URL(workspace.dataset.boardEventsUrl, window.location.origin);
      if (workspace.dataset.boardRevision) {
        url.searchParams.set("revision", workspace.dataset.boardRevision);
      }
      return `${url.pathname}${url.search}`;
    };

    const retryRealtimeSync = (source = null, minimumDelay = 0) => {
      if (source && realtimeSource !== source) return;
      source?.close();
      realtimeSource = null;
      realtimeConnected = false;
      setRealtimeState("reconnecting");
      window.clearTimeout(realtimeRestartTimer);
      const delay = Math.max(minimumDelay, realtimeRetryDelay)
        + Math.floor(Math.random() * 500);
      realtimeRetryDelay = Math.min(realtimeRetryDelay * 2, 30000);
      if (
        !boardCleanedUp
        && workspace.isConnected
        && document.visibilityState === "visible"
        && navigator.onLine
      ) {
        realtimeRestartTimer = window.setTimeout(startRealtimeSync, delay);
      }
      scheduleBoardPoll(Math.min(delay, 2500));
    };

    const startRealtimeSync = () => {
      if (
        !realtimeEnabled
        || boardCleanedUp
        || !workspace.isConnected
        || !workspace.dataset.boardEventsUrl
        || document.visibilityState !== "visible"
        || !navigator.onLine
      ) return;
      if (!("EventSource" in window)) {
        setRealtimeState("reconnecting");
        scheduleBoardPoll(2500);
        return;
      }

      realtimeSource?.close();
      realtimeSource = null;
      realtimeConnected = false;
      setRealtimeState("connecting");
      let source;
      try {
        source = new EventSource(realtimeEventsUrl());
      } catch (error) {
        retryRealtimeSync();
        return;
      }
      realtimeSource = source;

      source.addEventListener("connected", (streamEvent) => {
        if (realtimeSource !== source) return;
        let serverRevision = "";
        try {
          const payload = JSON.parse(streamEvent.data || "{}");
          serverRevision = payload.revision ?? payload.REVISION ?? "";
        } catch (error) {
          retryRealtimeSync(source, 500);
          return;
        }
        if (
          serverRevision
          && workspace.dataset.boardRevision
          && serverRevision !== workspace.dataset.boardRevision
        ) {
          source.close();
          realtimeSource = null;
          realtimeConnected = false;
          refreshBoard();
          return;
        }
        realtimeConnected = true;
        realtimeRetryDelay = 1000;
        setRealtimeState("live");
        scheduleBoardPoll();
      });

      source.addEventListener("board.updated", (streamEvent) => {
        if (realtimeSource !== source) return;
        let revision = "";
        try {
          const payload = JSON.parse(streamEvent.data || "{}");
          revision = payload.revision ?? payload.REVISION ?? "";
        } catch (error) {
          // The revision poll remains the source of truth for malformed events.
        }
        source.close();
        realtimeSource = null;
        realtimeConnected = false;
        if (revision && revision === workspace.dataset.boardRevision) {
          restartRealtimeSync(150);
          return;
        }
        setRealtimeState("reconnecting");
        refreshBoard();
      });

      source.addEventListener("reconnect", () => {
        if (realtimeSource !== source) return;
        restartRealtimeSync(250);
      });

      source.onerror = () => {
        if (realtimeSource !== source || boardCleanedUp) return;
        retryRealtimeSync(source);
      };
    };

    const restartRealtimeSync = (delay = 0) => {
      if (!realtimeEnabled || boardCleanedUp || !workspace.isConnected) return;
      stopRealtimeSync();
      setRealtimeState(delay ? "reconnecting" : "connecting");
      realtimeRestartTimer = window.setTimeout(startRealtimeSync, delay);
    };

    const cleanupBoardSync = () => {
      boardCleanedUp = true;
      window.clearTimeout(pollTimer);
      pollController?.abort();
      boardRefreshController?.abort();
      stopRealtimeSync();
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      window.removeEventListener("online", handleOnline);
      document.body.removeEventListener("htmx:beforeRequest", handleWorkspaceHtmxRequest);
    };

    const refreshBoard = async (url = workspace.dataset.boardRefreshUrl) => {
      if (boardRefreshPending || !workspace.isConnected) return;
      if (boardIsBusy()) {
        scheduleBoardPoll(750);
        return;
      }
      boardRefreshPending = true;
      const scrollLeft = workspace.querySelector(".workspace-board")?.scrollLeft || 0;
      boardRefreshController?.abort();
      boardRefreshController = new AbortController();
      try {
        const response = await fetch(url, {
          headers: {
            Accept: "text/html",
            "HX-Request": "true",
            "HX-Target": "workspace-main",
          },
          cache: "no-store",
          credentials: "same-origin",
          signal: boardRefreshController.signal,
        });
        const responsePath = new URL(response.url, window.location.origin).pathname;
        if (response.redirected && ["/login", "/check-email"].includes(responsePath)) {
          window.location.assign(response.url);
          return;
        }
        if (!response.ok || !response.headers.get("content-type")?.includes("text/html")) {
          throw new Error("Board refresh failed");
        }
        const html = await response.text();
        if (
          !workspace.isConnected
          || document.getElementById("workspace-main") !== workspace
          || boardIsBusy()
          || document.visibilityState !== "visible"
          || !navigator.onLine
        ) {
          scheduleBoardPoll(750);
          return;
        }
        const parsed = new DOMParser().parseFromString(html, "text/html");
        const replacement = parsed.querySelector("#workspace-main");
        if (!replacement) throw new Error("Board refresh markup is missing");
        const refreshedTitle = parsed.querySelector("title")?.textContent;
        cleanupBoardSync();
        workspace.replaceWith(replacement);
        if (refreshedTitle) document.title = refreshedTitle;
        window.htmx?.process(replacement);
        initDynamicContent(replacement);
        replacement.querySelector(".workspace-board")?.scrollTo({ left: scrollLeft });
      } catch (error) {
        if (error.name !== "AbortError") scheduleBoardPoll(2500);
      } finally {
        boardRefreshPending = false;
        if (!boardCleanedUp && workspace.isConnected) scheduleBoardPoll(2500);
      }
    };

    const scheduleBoardPoll = (
      delay = (
        realtimeEnabled
          ? (realtimeConnected ? 30000 : 10000)
          : 30000
      ) + Math.floor(Math.random() * 1500),
    ) => {
      window.clearTimeout(pollTimer);
      if (!boardCleanedUp && workspace.isConnected) {
        pollTimer = window.setTimeout(pollBoardRevision, delay);
      }
    };

    const pollBoardRevision = async () => {
      updateViewedLabel();
      if (boardCleanedUp || !workspace.isConnected) return;
      if (document.visibilityState !== "visible" || !navigator.onLine) return;
      if (boardIsBusy()) {
        scheduleBoardPoll(2500);
        return;
      }

      pollController?.abort();
      pollController = new AbortController();
      const currentRevision = workspace.dataset.boardRevision;
      const etag = `"board-${workspace.dataset.boardId.toLowerCase()}-${currentRevision}"`;
      try {
        const response = await fetch(workspace.dataset.boardRevisionUrl, {
          headers: { Accept: "application/json", "If-None-Match": etag },
          cache: "no-store",
          signal: pollController.signal,
        });
        const responsePath = new URL(response.url, window.location.origin).pathname;
        if (response.redirected && ["/login", "/check-email"].includes(responsePath)) {
          window.location.assign(response.url);
          return;
        }
        if (response.status === 304) {
          scheduleBoardPoll();
          return;
        }
        if (response.status === 404) {
          refreshBoard("/app");
          return;
        }
        if (!response.ok) throw new Error("Revision request failed");
        if (!response.headers.get("content-type")?.includes("application/json")) {
          throw new Error("Revision response is not JSON");
        }
        const result = await response.json();
        const revision = result.revision ?? result.REVISION;
        if (revision && revision !== currentRevision) {
          if (boardIsBusy() || document.visibilityState !== "visible" || !navigator.onLine) {
            scheduleBoardPoll(750);
            return;
          }
          refreshBoard();
          return;
        }
      } catch (error) {
        if (error.name === "AbortError") return;
      }
      scheduleBoardPoll();
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        restartRealtimeSync(100);
        scheduleBoardPoll(500);
      } else {
        stopRealtimeSync();
      }
    };
    const handleOnline = () => {
      restartRealtimeSync(100);
      scheduleBoardPoll(500);
    };
    const handleWorkspaceHtmxRequest = (event) => {
      const requestTarget = event.detail?.target;
      if (requestTarget === workspace || requestTarget?.id === "workspace-main") {
        boardRefreshController?.abort();
      }
    };
    if (!workspace.dataset.boardId || !workspace.dataset.boardRevisionUrl) return;
    workspace.addEventListener("htmx:beforeCleanupElement", cleanupBoardSync, { once: true });
    document.addEventListener("visibilitychange", handleVisibilityChange);
    window.addEventListener("online", handleOnline);
    document.body.addEventListener("htmx:beforeRequest", handleWorkspaceHtmxRequest);
    updateViewedLabel();
    restartRealtimeSync();
    scheduleBoardPoll();
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

  const initAvatarManager = (root) => {
    const manager = root.matches?.("[data-avatar-manager]")
      ? root
      : root.querySelector?.("[data-avatar-manager]");
    if (!manager || manager.dataset.avatarInitialized) return;
    manager.dataset.avatarInitialized = "true";

    const fileInput = manager.querySelector("[data-avatar-file]");
    const editor = manager.querySelector("[data-avatar-editor]");
    const stage = manager.querySelector("[data-avatar-stage]");
    const cropImage = manager.querySelector("[data-avatar-crop-image]");
    const zoomInput = manager.querySelector("[data-avatar-zoom]");
    const saveButton = manager.querySelector("[data-avatar-save]");
    const cancelButton = manager.querySelector("[data-avatar-cancel]");
    const removeButton = manager.querySelector("[data-avatar-remove]");
    const status = manager.querySelector("[data-avatar-status]");
    const allowedTypes = ["image/jpeg", "image/png", "image/webp"];
    const maxSourceBytes = Number(manager.dataset.avatarMaxSourceBytes) || 5242880;
    const outputPixels = 512;
    const maxSourceDimension = 16384;
    const maxSourcePixels = 60000000;
    const maxWorkingDimension = 4096;
    const maxWorkingPixels = 12582912;
    let sourceFile = null;
    let normalizedUrl = "";
    let naturalWidth = 0;
    let naturalHeight = 0;
    let zoom = 1;
    let offsetX = 0;
    let offsetY = 0;
    let dragState = null;

    const responseValue = (payload, key) => payload?.[key] ?? payload?.[key.toUpperCase()];
    const messageForCode = (code) => {
      const suffix = String(code || "generic")
        .replaceAll("-", "_")
        .replace(/_([a-z])/g, (_, letter) => letter.toUpperCase())
        .replace(/^([a-z])/, (_, letter) => letter.toUpperCase());
      return manager.dataset[`avatar${suffix}`] || manager.dataset.avatarGenericError;
    };
    const setStatus = (message, success = false) => {
      status.textContent = message || "";
      status.classList.toggle("success", success);
    };
    const stageSize = () => stage?.clientWidth || 280;
    const currentScale = () =>
      Math.max(stageSize() / naturalWidth, stageSize() / naturalHeight) * zoom;
    const clampOffsets = () => {
      const scale = currentScale();
      const maxX = Math.max(0, (naturalWidth * scale - stageSize()) / 2);
      const maxY = Math.max(0, (naturalHeight * scale - stageSize()) / 2);
      offsetX = Math.max(-maxX, Math.min(maxX, offsetX));
      offsetY = Math.max(-maxY, Math.min(maxY, offsetY));
    };
    const renderCrop = () => {
      if (!naturalWidth || !naturalHeight) return;
      clampOffsets();
      const scale = currentScale();
      cropImage.style.width = `${naturalWidth * scale}px`;
      cropImage.style.height = `${naturalHeight * scale}px`;
      cropImage.style.transform =
        `translate(calc(-50% + ${offsetX}px), calc(-50% + ${offsetY}px))`;
    };
    const cropResizeObserver =
      typeof ResizeObserver === "function" && stage
        ? new ResizeObserver(() => {
            if (!editor.hidden) renderCrop();
          })
        : null;
    cropResizeObserver?.observe(stage);
    manager.addEventListener(
      "htmx:beforeCleanupElement",
      () => cropResizeObserver?.disconnect(),
      { once: true }
    );
    const closeEditor = () => {
      editor.hidden = true;
      sourceFile = null;
      fileInput.value = "";
      dragState = null;
      stage?.classList.remove("dragging");
      if (normalizedUrl) URL.revokeObjectURL(normalizedUrl);
      normalizedUrl = "";
      cropImage.removeAttribute("src");
    };
    const normalizeSource = async (file) => {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
      try {
        const sourcePixels = bitmap.width * bitmap.height;
        if (
          !bitmap.width ||
          !bitmap.height ||
          bitmap.width > maxSourceDimension ||
          bitmap.height > maxSourceDimension ||
          sourcePixels > maxSourcePixels
        ) {
          throw new Error("source_dimensions");
        }
        const workingScale = Math.min(
          1,
          maxWorkingDimension / bitmap.width,
          maxWorkingDimension / bitmap.height,
          Math.sqrt(maxWorkingPixels / sourcePixels)
        );
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(bitmap.width * workingScale));
        canvas.height = Math.max(1, Math.round(bitmap.height * workingScale));
        const context = canvas.getContext("2d", { alpha: false });
        if (!context) throw new Error("invalid_output");
        context.imageSmoothingEnabled = true;
        context.imageSmoothingQuality = "high";
        context.fillStyle = "#ffffff";
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
        const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92));
        if (!blob) throw new Error("invalid_output");
        return blob;
      } finally {
        bitmap.close?.();
      }
    };
    const loadSource = async (file) => {
      if (!allowedTypes.includes(file.type)) {
        setStatus(manager.dataset.avatarInvalidType);
        fileInput.value = "";
        return;
      }
      if (!file.size || file.size > maxSourceBytes) {
        setStatus(manager.dataset.avatarSourceTooLarge);
        fileInput.value = "";
        return;
      }
      setStatus("");
      try {
        const normalized = await normalizeSource(file);
        if (normalizedUrl) URL.revokeObjectURL(normalizedUrl);
        normalizedUrl = URL.createObjectURL(normalized);
        cropImage.src = normalizedUrl;
        await cropImage.decode();
        sourceFile = file;
        naturalWidth = cropImage.naturalWidth;
        naturalHeight = cropImage.naturalHeight;
        zoom = 1;
        offsetX = 0;
        offsetY = 0;
        zoomInput.value = "1";
        editor.hidden = false;
        renderCrop();
        stage.focus();
      } catch (error) {
        setStatus(messageForCode(error.message));
        closeEditor();
      }
    };
    const createOutput = async () => {
      const scale = currentScale();
      const sourceWidth = stageSize() / scale;
      const sourceHeight = stageSize() / scale;
      const sourceX = (naturalWidth - sourceWidth) / 2 - offsetX / scale;
      const sourceY = (naturalHeight - sourceHeight) / 2 - offsetY / scale;
      const canvas = document.createElement("canvas");
      canvas.width = outputPixels;
      canvas.height = outputPixels;
      const context = canvas.getContext("2d", { alpha: false });
      context.fillStyle = "#ffffff";
      context.fillRect(0, 0, outputPixels, outputPixels);
      context.drawImage(
        cropImage,
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
        0,
        0,
        outputPixels,
        outputPixels
      );
      let output = null;
      for (const quality of [0.9, 0.82, 0.72]) {
        output = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));
        if (output && output.size <= 1048576) break;
      }
      if (!output) throw new Error("invalid_output");
      if (output.size > 1048576) throw new Error("output_too_large");
      return output;
    };
    const updateCurrentAvatar = (url = "") => {
      document.querySelectorAll("[data-current-user-avatar]").forEach((avatar) => {
        avatar.querySelector("img")?.remove();
        if (url) {
          const image = document.createElement("img");
          image.src = url;
          image.alt = "";
          avatar.append(image);
        }
      });
    };
    const refreshAvatarPanel = () => {
      if (window.htmx && document.querySelector("#profile-avatar")) {
        window.htmx.ajax("GET", "/app/profile", {
          target: "#profile-avatar",
          select: "#profile-avatar",
          swap: "outerHTML",
        });
      } else {
        window.location.assign("/app/profile");
      }
    };
    const uploadCrop = async () => {
      if (!sourceFile) return;
      saveButton.disabled = true;
      cancelButton.disabled = true;
      setStatus(manager.dataset.avatarUploading);
      try {
        const output = await createOutput();
        const csrfToken = manager.dataset.avatarCsrfToken;
        const presignResponse = await fetch(manager.dataset.avatarPresignUrl, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
          body: new URLSearchParams({
            csrfToken,
            filename: sourceFile.name,
            sourceContentType: sourceFile.type,
            sourceSize: String(sourceFile.size),
            outputSize: String(output.size),
          }),
        });
        const presign = await presignResponse.json();
        if (!presignResponse.ok || !responseValue(presign, "success")) {
          throw new Error(responseValue(presign, "code") || "generic");
        }
        const avatarId = responseValue(presign, "id");
        const uploadResponse = await fetch(responseValue(presign, "uploadUrl"), {
          method: "PUT",
          headers: { "Content-Type": "image/jpeg" },
          body: output,
        });
        if (!uploadResponse.ok) throw new Error("invalid_output");
        const completeResponse = await fetch(
          manager.dataset.avatarCompleteUrlTemplate.replace("{id}", encodeURIComponent(avatarId)),
          {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
            body: new URLSearchParams({ csrfToken }),
          }
        );
        const completed = await completeResponse.json();
        if (!completeResponse.ok || !responseValue(completed, "success")) {
          throw new Error(responseValue(completed, "code") || "generic");
        }
        const avatarUrl = responseValue(completed, "url");
        updateCurrentAvatar(avatarUrl);
        setStatus(manager.dataset.avatarSaved, true);
        closeEditor();
        refreshAvatarPanel();
      } catch (error) {
        setStatus(messageForCode(error.message));
      } finally {
        saveButton.disabled = false;
        cancelButton.disabled = false;
      }
    };
    const removeAvatar = async () => {
      if (!window.confirm(manager.dataset.avatarRemoveConfirm)) return;
      removeButton.disabled = true;
      setStatus(manager.dataset.avatarUploading);
      try {
        const response = await fetch(manager.dataset.avatarRemoveUrl, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
          body: new URLSearchParams({ csrfToken: manager.dataset.avatarCsrfToken }),
        });
        const result = await response.json();
        if (!response.ok || !responseValue(result, "success")) {
          throw new Error(responseValue(result, "code") || "generic");
        }
        updateCurrentAvatar("");
        setStatus(manager.dataset.avatarRemoved, true);
        refreshAvatarPanel();
      } catch (error) {
        setStatus(messageForCode(error.message));
        removeButton.disabled = false;
      }
    };

    fileInput?.addEventListener("change", () => {
      const file = fileInput.files?.[0];
      if (file) loadSource(file);
    });
    zoomInput?.addEventListener("input", () => {
      zoom = Number(zoomInput.value) || 1;
      renderCrop();
    });
    stage?.addEventListener("pointerdown", (event) => {
      if (editor.hidden) return;
      dragState = { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
      stage.setPointerCapture?.(event.pointerId);
      stage.classList.add("dragging");
    });
    stage?.addEventListener("pointermove", (event) => {
      if (!dragState || dragState.pointerId !== event.pointerId) return;
      offsetX += event.clientX - dragState.x;
      offsetY += event.clientY - dragState.y;
      dragState.x = event.clientX;
      dragState.y = event.clientY;
      renderCrop();
    });
    const finishDrag = (event) => {
      if (!dragState || dragState.pointerId !== event.pointerId) return;
      dragState = null;
      stage.classList.remove("dragging");
    };
    stage?.addEventListener("pointerup", finishDrag);
    stage?.addEventListener("pointercancel", finishDrag);
    stage?.addEventListener("keydown", (event) => {
      const movement = event.shiftKey ? 15 : 5;
      if (event.key === "Escape") {
        event.preventDefault();
        closeEditor();
      } else if (event.key === "+" || event.key === "=") {
        event.preventDefault();
        zoom = Math.min(3, zoom + 0.1);
        zoomInput.value = String(zoom);
        renderCrop();
      } else if (event.key === "-") {
        event.preventDefault();
        zoom = Math.max(1, zoom - 0.1);
        zoomInput.value = String(zoom);
        renderCrop();
      } else if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)) {
        event.preventDefault();
        if (event.key === "ArrowLeft") offsetX -= movement;
        if (event.key === "ArrowRight") offsetX += movement;
        if (event.key === "ArrowUp") offsetY -= movement;
        if (event.key === "ArrowDown") offsetY += movement;
        renderCrop();
      }
    });
    cancelButton?.addEventListener("click", closeEditor);
    saveButton?.addEventListener("click", uploadCrop);
    removeButton?.addEventListener("click", removeAvatar);
  };

  const initIntegrationReveal = (root) => {
    const reveal = root.matches?.("[data-integration-reveal]")
      ? root
      : root.querySelector?.("[data-integration-reveal]");
    if (!reveal || reveal.dataset.integrationRevealInitialized) return;
    reveal.dataset.integrationRevealInitialized = "true";
    const copyButton = reveal.querySelector("[data-integration-copy]");
    const secret = reveal.querySelector("[data-integration-secret]");
    copyButton?.addEventListener("click", async () => {
      if (!secret) return;
      const value = secret.textContent.trim();
      try {
        await navigator.clipboard.writeText(value);
      } catch (error) {
        const temporary = document.createElement("textarea");
        temporary.value = value;
        temporary.setAttribute("readonly", "");
        temporary.style.position = "fixed";
        temporary.style.opacity = "0";
        document.body.appendChild(temporary);
        temporary.select();
        document.execCommand("copy");
        temporary.remove();
      }
      const label = copyButton.querySelector("span");
      if (label) label.textContent = reveal.dataset.copiedLabel;
      copyButton.classList.add("copied");
    });
  };

  const updateWorkspaceNavigation = (root) => {
    const workspaceMain = root.matches?.("[data-workspace-page]")
      ? root
      : root.querySelector?.("[data-workspace-page]");
    if (!workspaceMain || !workspaceShell) return;
    const page = workspaceMain.dataset.workspacePage;
    const paths = {
      myWork: "/app/my-work",
      app: "/app",
      members: "/app/members",
      notifications: "/app/notifications",
      analytics: "/app/analytics",
      automations: "/app/automations",
      settings: "/app/settings",
      integrations: "/app/settings",
    };

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

    const workspaceName = workspaceMain.dataset.workspaceName?.trim();
    if (workspaceName) {
      workspaceShell.querySelectorAll("[data-current-workspace-name]").forEach((element) => {
        element.textContent = workspaceName;
      });
      workspaceShell.querySelectorAll("[data-current-workspace-initial]").forEach((element) => {
        element.textContent = workspaceName.charAt(0).toUpperCase();
      });
    }

    const workspaceRoleLabel = workspaceMain.dataset.workspaceRoleLabel?.trim();
    if (workspaceRoleLabel) {
      workspaceShell.querySelectorAll("[data-current-workspace-role]").forEach((element) => {
        element.textContent = workspaceRoleLabel;
      });
    }

    document.body.className = `page-${page}`;
  };

  const initDynamicContent = (root) => {
    initPendingBilling(root);
    initWorkspaceBoard(root);
    initCardDetails(root);
    initAttachments(root);
    initAvatarManager(root);
    initIntegrationReveal(root);
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
  document.body.addEventListener("htmx:beforeRequest", (event) => {
    const requestElement = event.detail?.elt;
    if (requestElement?.closest?.("[data-analytics-filters]")) {
      document.querySelector("#analytics-results")?.setAttribute("aria-busy", "true");
      const clientError = document.querySelector("[data-analytics-client-error]");
      if (clientError) clientError.hidden = true;
    }
    if (requestElement?.closest?.("#notification-list")) {
      document.querySelector("#notification-list")?.setAttribute("aria-busy", "true");
    }
  });
  document.body.addEventListener("htmx:afterRequest", (event) => {
    const requestElement = event.detail?.elt;
    if (requestElement?.closest?.("[data-analytics-filters]")) {
      document.querySelector("#analytics-results")?.setAttribute("aria-busy", "false");
    }
    if (requestElement?.closest?.("#notification-list")) {
      document.querySelector("#notification-list")?.setAttribute("aria-busy", "false");
    }
    if (requestElement?.closest?.("[data-notification-open]") && event.detail?.successful) {
      window.htmx?.trigger(document.body, "notification-read");
    }
  });
  ["htmx:sendError", "htmx:responseError", "htmx:timeout"].forEach((eventName) => {
    document.body.addEventListener(eventName, (event) => {
      const requestElement = event.detail?.elt;
      if (requestElement?.closest?.("[data-analytics-filters]")) {
        document.querySelector("#analytics-results")?.setAttribute("aria-busy", "false");
        const clientError = document.querySelector("[data-analytics-client-error]");
        if (clientError) clientError.hidden = false;
      }
      if (requestElement?.closest?.("#notification-list")) {
        document.querySelector("#notification-list")?.setAttribute("aria-busy", "false");
      }
    });
  });
})();
