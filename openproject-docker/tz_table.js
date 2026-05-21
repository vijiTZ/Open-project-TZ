// ============================================================================
//  TzTable — reusable, dependency-free, design-system-styled data table.
// ----------------------------------------------------------------------------
//  Bind-mounted to /app/public/tz-table.js inside the container and injected
//  into every HTML response via css_injector.rb. Defines a single global
//  `TzTable` you can call from any page or inline script.
//
//  Usage (matches the "tickets" reference mock — dark header, status pills,
//  avatar-with-dot, colored time, circular action button, active row):
//
//    <div id="tickets"></div>
//    <script>
//      TzTable.mount('#tickets', {
//        variant: 'dark',
//        activeRowId: 90686,
//        columns: [
//          { key: 'id',          label: 'ID' },
//          { key: 'title',       label: 'Problem Title' },
//          { key: 'technician',  label: 'Technician', type: 'avatar',
//                                statusKey: 'presence' },          // 'online'|'idle'|'offline'
//          { key: 'model',       label: 'Model' },
//          { key: 'dealer',      label: 'Dealer Code' },
//          { key: 'date',        label: 'Date', type: 'date',
//                                timeKey: 'sla',
//                                timeColorKey: 'slaLevel' },        // 'danger'|'warn'
//          { key: 'status',      label: 'Status', type: 'status' }, // see status map below
//          {                     label: 'Action', type: 'actions' },
//        ],
//        rows: [
//          { id: 90686, title: 'Gear indication not show...',
//            technician: 'Ansari Mustufa M', presence: 'online',
//            model: 'Motorcycles, TVS Ronin', dealer: '14360',
//            date: '2026-02-19', sla: '15:34min', slaLevel: 'danger',
//            status: 'opened' },
//          // 'opened' | 'closed' | 'reopened' | 'in-progress'
//        ],
//        rowKey: 'id',
//        actions: [
//          { icon: '⋯', label: 'More', onClick: (row) => console.log(row) },
//        ],
//      });
//    </script>
//
//  Column types:
//    text       — default; renders `String(row[key])`
//    avatar     — round initial circle + name. Options:
//                   avatarKey  — field for the initial letter (defaults to first char of value)
//                   colorKey   — field whose value is hashed to pick the bg color
//                   statusKey  — field with 'online'|'idle'|'offline'|'busy' for the corner dot
//    yesno      — green "Yes" when truthy, dim "No" otherwise
//    date       — formats ISO/Date as "MMM DD, YY". Options:
//                   timeKey       — second field rendered as " | 15:34min" suffix
//                   timeColorKey  — field whose value ('danger'|'warn'|'ok') colors the time
//    datetime   — formats ISO/Date as "MM/DD/YYYY | hh:mm AM"
//    status     — colored pill with icon. row[key] is one of:
//                   'opened' | 'closed' | 'reopened' | 'in-progress'
//                 Or pass `col.statusMap = { mykey: { label, tone, icon } }` to extend.
//    badge      — plain colored pill; `colorKey` chooses the row field to read color from
//    link       — anchor tag; `hrefKey` (or `href` function) for the URL
//    actions    — right-aligned cluster of circular icon buttons (config.actions[])
//    select     — managed automatically when `selectable: true`; you do not need
//                 to declare it
//    custom     — `render(row)` returns the cell HTML string (use carefully —
//                 you are responsible for escaping)
//
//  Config:
//    variant       — '' (default, light header) | 'dark' (navy header w/ white text)
//    activeRowId   — id of the row to highlight with a blue border (matches mock)
//
//  Styling: the rendered HTML uses class="tz-table" + .tz-table-container,
//  which are styled in openproject-custom.css (sections 6, 10, 12). No CSS
//  changes needed to consume the component.
// ============================================================================

(function (global) {
  "use strict";

  // ─── helpers ────────────────────────────────────────────────────────────
  const escapeHtml = (s) =>
    String(s == null ? "" : s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");

  const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

  const fmtDate = (v) => {
    if (!v) return "";
    const d = v instanceof Date ? v : new Date(v);
    if (isNaN(d)) return escapeHtml(v);
    const mm = MONTHS[d.getMonth()];
    const dd = String(d.getDate()).padStart(2, "0");
    const yy = String(d.getFullYear()).slice(-2);
    return `${mm} ${dd}, ${yy}`;
  };

  const fmtDateTime = (v) => {
    if (!v) return "";
    const d = v instanceof Date ? v : new Date(v);
    if (isNaN(d)) return escapeHtml(v);
    const mm = String(d.getMonth() + 1).padStart(2, "0");
    const dd = String(d.getDate()).padStart(2, "0");
    let h = d.getHours();
    const min = String(d.getMinutes()).padStart(2, "0");
    const ampm = h >= 12 ? "PM" : "AM";
    h = h % 12 || 12;
    return `${mm}/${dd}/${d.getFullYear()} | ${String(h).padStart(2, "0")}:${min} ${ampm}`;
  };

  const initialOf = (s) => {
    const t = String(s || "").trim();
    return t ? t[0].toUpperCase() : "?";
  };

  // Stable hash → palette index, so the same name always gets the same color.
  const AVATAR_PALETTE = [
    { bg: "#dbeafe", fg: "#1d4ed8" }, // blue
    { bg: "#fde68a", fg: "#92400e" }, // amber
    { bg: "#dcfce7", fg: "#166534" }, // green
    { bg: "#fce7f3", fg: "#9d174d" }, // pink
    { bg: "#e0e7ff", fg: "#3730a3" }, // indigo
    { bg: "#cffafe", fg: "#155e75" }, // cyan
    { bg: "#fee2e2", fg: "#991b1b" }, // red
    { bg: "#ede9fe", fg: "#5b21b6" }, // violet
  ];
  const pickAvatarColor = (seed) => {
    const s = String(seed || "");
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
    return AVATAR_PALETTE[h % AVATAR_PALETTE.length];
  };

  // ─── status pills ───────────────────────────────────────────────────────
  // Each entry: label shown in the pill, tone (CSS modifier), and an inline
  // SVG icon. Icons are tiny (12px) so they sit clean inside the pill.
  const ICON = {
    dotCircle: `<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="1.5"/><circle cx="8" cy="8" r="2.5" fill="currentColor"/></svg>`,
    check:     `<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><circle cx="8" cy="8" r="6.5" fill="currentColor" opacity="0.18"/><path d="M5 8.2l2.2 2.2L11 6.6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
    refresh:   `<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path d="M13 8a5 5 0 1 1-1.46-3.54M13 3.5V6H10.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
    clock:     `<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><circle cx="8" cy="8" r="6.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M8 4.5V8l2.2 1.4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`,
  };

  const DEFAULT_STATUS_MAP = {
    "opened":      { label: "Opened",      tone: "opened",  icon: ICON.dotCircle },
    "open":        { label: "Opened",      tone: "opened",  icon: ICON.dotCircle },
    "closed":      { label: "Closed",      tone: "closed",  icon: ICON.check },
    "resolved":    { label: "Closed",      tone: "closed",  icon: ICON.check },
    "reopened":    { label: "Reopend",     tone: "reopened",icon: ICON.refresh },
    "reopend":     { label: "Reopend",     tone: "reopened",icon: ICON.refresh },
    "in-progress": { label: "In Progress", tone: "progress",icon: ICON.clock },
    "in_progress": { label: "In Progress", tone: "progress",icon: ICON.clock },
    "progress":    { label: "In Progress", tone: "progress",icon: ICON.clock },
  };

  const SORT_ARROWS = `<span class="tz-sort-arrows" aria-hidden="true"><span class="tz-sort-up">▲</span><span class="tz-sort-down">▼</span></span>`;

  const resolveTarget = (target) => {
    if (typeof target === "string") return document.querySelector(target);
    if (target instanceof HTMLElement) return target;
    return null;
  };

  // ─── cell renderers ─────────────────────────────────────────────────────
  function renderCell(col, row, ctx) {
    const v = row[col.key];
    switch (col.type) {
      case "avatar": {
        const name = String(v == null ? "" : v);
        const initial = col.avatarKey
          ? escapeHtml(row[col.avatarKey])
          : escapeHtml(initialOf(name));
        const seed = col.colorKey ? row[col.colorKey] : name;
        const c = pickAvatarColor(seed);
        const presence = col.statusKey ? String(row[col.statusKey] || "").toLowerCase() : "";
        const dot = presence
          ? `<span class="tz-avatar-dot tz-avatar-dot--${escapeHtml(presence)}" aria-hidden="true"></span>`
          : "";
        return (
          `<span class="tz-cell-avatar">` +
            `<span class="tz-avatar-wrap">` +
              `<span class="tz-avatar" aria-hidden="true" style="background:${c.bg};color:${c.fg}">${initial}</span>` +
              dot +
            `</span>` +
            `<span class="tz-avatar-name">${escapeHtml(name)}</span>` +
          `</span>`
        );
      }
      case "yesno":
        return v
          ? `<span class="tz-cell-yes">Yes</span>`
          : `<span class="tz-cell-no">No</span>`;
      case "date": {
        const main = fmtDate(v);
        if (!col.timeKey) return main;
        const t = row[col.timeKey];
        if (t == null || t === "") return main;
        const level = col.timeColorKey ? String(row[col.timeColorKey] || "").toLowerCase() : "warn";
        return `${main} <span class="tz-cell-date-time tz-cell-date-time--${escapeHtml(level)}">| ${escapeHtml(t)}</span>`;
      }
      case "datetime":
        return fmtDateTime(v);
      case "status": {
        const map = Object.assign({}, DEFAULT_STATUS_MAP, col.statusMap || {});
        const key = String(v == null ? "" : v).toLowerCase().trim();
        const def = map[key] || { label: String(v == null ? "" : v), tone: "neutral", icon: ICON.dotCircle };
        return `<span class="tz-status tz-status--${escapeHtml(def.tone)}">${def.icon}<span class="tz-status-label">${escapeHtml(def.label)}</span></span>`;
      }
      case "badge": {
        const color = col.colorKey ? row[col.colorKey] : col.color;
        const style = color ? ` style="color:${escapeHtml(color)}"` : "";
        return `<span class="tz-cell-badge"${style}>${escapeHtml(v)}</span>`;
      }
      case "link": {
        const href = typeof col.href === "function"
          ? col.href(row)
          : row[col.hrefKey || "href"] || "#";
        return `<a href="${escapeHtml(href)}">${escapeHtml(v)}</a>`;
      }
      case "actions":
        return ctx.actions
          .map(
            (a, i) =>
              `<button type="button" class="tz-action-btn" data-tz-action="${i}" aria-label="${escapeHtml(a.label || "")}">${escapeHtml(a.icon || "⋯")}</button>`
          )
          .join("");
      case "custom":
        return typeof col.render === "function" ? col.render(row) : escapeHtml(v);
      default:
        return escapeHtml(v);
    }
  }

  function renderHeaderCell(col, ctx) {
    if (col.type === "select") {
      return `<th class="tz-select-cell"><input type="checkbox" class="tz-master-checkbox" aria-label="Select all"></th>`;
    }
    if (col.type === "actions") {
      return `<th class="actions" style="text-align:right">${escapeHtml(col.label || "Action")}</th>`;
    }
    const isSortable = ctx.sortable && col.sortable !== false;
    const sortableAttr = isSortable ? " data-tz-sortable" : "";
    const arrows = isSortable ? SORT_ARROWS : "";
    const sortedCls =
      ctx.sortKey === col.key
        ? ` tz-sorted tz-sorted--${ctx.sortDir}`
        : "";
    return (
      `<th${sortableAttr} class="tz-th${sortedCls}" data-tz-key="${escapeHtml(col.key)}">` +
        `<span class="tz-th-inner">` +
          `<span class="tz-th-label">${escapeHtml(col.label || col.key)}</span>` +
          arrows +
        `</span>` +
      `</th>`
    );
  }

  // ─── core component ─────────────────────────────────────────────────────
  function mount(target, configIn) {
    const root = resolveTarget(target);
    if (!root) {
      console.error("[TzTable] target not found:", target);
      return null;
    }

    const config = Object.assign(
      {
        columns: [],
        rows: [],
        rowKey: "id",
        selectable: false,
        pageSize: 0,
        pageSizes: [10, 25, 50, 100],
        sortable: true,
        actions: [],
        variant: "",          // '' | 'dark'
        activeRowId: null,    // id of the row to highlight with the blue border
        onSelectionChange: null,
        onSortChange: null,
        onPageChange: null,
      },
      configIn || {}
    );

    const columns = config.selectable && !config.columns.some((c) => c.type === "select")
      ? [{ type: "select", key: "__select" }].concat(config.columns)
      : config.columns.slice();

    const state = {
      rows: config.rows.slice(),
      sortKey: null,
      sortDir: "asc",
      page: 1,
      pageSize: config.pageSize || 0,
      selection: new Set(),
    };

    function visibleRows() {
      let rows = state.rows;
      if (state.sortKey) {
        const k = state.sortKey;
        const dir = state.sortDir === "asc" ? 1 : -1;
        rows = rows.slice().sort((a, b) => {
          const av = a[k], bv = b[k];
          if (av == null) return 1;
          if (bv == null) return -1;
          if (av < bv) return -1 * dir;
          if (av > bv) return 1 * dir;
          return 0;
        });
      }
      if (state.pageSize > 0) {
        const start = (state.page - 1) * state.pageSize;
        return rows.slice(start, start + state.pageSize);
      }
      return rows;
    }

    function totalPages() {
      if (!state.pageSize) return 1;
      return Math.max(1, Math.ceil(state.rows.length / state.pageSize));
    }

    function render() {
      const pageRows = visibleRows();
      const ctx = {
        actions: config.actions,
        sortable: config.sortable,
        sortKey: state.sortKey,
        sortDir: state.sortDir,
      };

      const headHtml = columns.map((c) => renderHeaderCell(c, ctx)).join("");
      const bodyHtml = pageRows.length === 0
        ? `<tr class="tz-table--empty-row"><td colspan="${columns.length}">No data</td></tr>`
        : pageRows
            .map((row) => {
              const id = String(row[config.rowKey]);
              const checked = state.selection.has(id) ? " checked" : "";
              const isActive = config.activeRowId != null && String(config.activeRowId) === id;
              const rowCls = isActive ? " tz-row--active" : "";
              const cells = columns
                .map((col) => {
                  if (col.type === "select") {
                    return `<td class="tz-select-cell"><input type="checkbox" class="tz-row-checkbox" value="${escapeHtml(id)}"${checked} aria-label="Select row"></td>`;
                  }
                  if (col.type === "actions") {
                    return `<td class="actions" style="text-align:right">${renderCell(col, row, ctx)}</td>`;
                  }
                  return `<td class="${escapeHtml(col.key)}">${renderCell(col, row, ctx)}</td>`;
                })
                .join("");
              return `<tr class="tz-row${rowCls}" data-tz-row-id="${escapeHtml(id)}">${cells}</tr>`;
            })
            .join("");

      const footerHtml = state.pageSize ? renderFooter(pageRows.length) : "";

      const variantCls = config.variant === "dark" ? " tz-table--dark" : "";
      root.innerHTML = `
        <div class="tz-table-container${variantCls ? " tz-table-container--dark" : ""}">
          <table class="tz-table generic-table${variantCls}">
            <thead><tr>${headHtml}</tr></thead>
            <tbody>${bodyHtml}</tbody>
          </table>
          ${footerHtml}
        </div>
      `;

      wireEvents();
      syncMaster();
    }

    function renderFooter(visibleCount) {
      const total = state.rows.length;
      const from = total === 0 ? 0 : (state.page - 1) * state.pageSize + 1;
      const to = Math.min(total, from + visibleCount - 1);
      const tp = totalPages();

      const sizes = config.pageSizes
        .map(
          (n) =>
            `<option value="${n}"${n === state.pageSize ? " selected" : ""}>${n} per page</option>`
        )
        .join("");

      return `
        <div class="tz-table-footer">
          <span class="tz-table-summary">Showing ${from} to ${to} of ${total} entries</span>
          <span class="tz-table-pager">
            <select class="tz-page-size">${sizes}</select>
            <button type="button" class="tz-page-prev" ${state.page <= 1 ? "disabled" : ""}>‹</button>
            <span class="tz-page-current">${from}-${to}</span>
            <button type="button" class="tz-page-next" ${state.page >= tp ? "disabled" : ""}>›</button>
          </span>
        </div>
      `;
    }

    function wireEvents() {
      const master = root.querySelector(".tz-master-checkbox");
      if (master) {
        master.addEventListener("change", () => {
          const pageRowIds = Array.from(root.querySelectorAll(".tz-row-checkbox")).map((el) => el.value);
          if (master.checked) pageRowIds.forEach((id) => state.selection.add(id));
          else pageRowIds.forEach((id) => state.selection.delete(id));
          root.querySelectorAll(".tz-row-checkbox").forEach((el) => (el.checked = master.checked));
          publishSelection();
        });
      }

      root.querySelectorAll(".tz-row-checkbox").forEach((el) => {
        el.addEventListener("change", () => {
          if (el.checked) state.selection.add(el.value);
          else state.selection.delete(el.value);
          syncMaster();
          publishSelection();
        });
      });

      if (config.sortable) {
        root.querySelectorAll("th[data-tz-sortable]").forEach((th) => {
          th.style.cursor = "pointer";
          th.addEventListener("click", () => {
            const key = th.dataset.tzKey;
            if (state.sortKey === key) {
              state.sortDir = state.sortDir === "asc" ? "desc" : "asc";
            } else {
              state.sortKey = key;
              state.sortDir = "asc";
            }
            if (config.onSortChange) config.onSortChange(state.sortKey, state.sortDir);
            render();
          });
        });
      }

      root.querySelectorAll("button[data-tz-action]").forEach((btn) => {
        btn.addEventListener("click", (e) => {
          e.stopPropagation();
          const idx = Number(btn.dataset.tzAction);
          const rowEl = btn.closest("tr");
          const id = rowEl && rowEl.dataset.tzRowId;
          const row = state.rows.find((r) => String(r[config.rowKey]) === id);
          const action = config.actions[idx];
          if (action && typeof action.onClick === "function") action.onClick(row, btn);
        });
      });

      const prev = root.querySelector(".tz-page-prev");
      const next = root.querySelector(".tz-page-next");
      const size = root.querySelector(".tz-page-size");
      if (prev)
        prev.addEventListener("click", () => {
          if (state.page > 1) {
            state.page--;
            if (config.onPageChange) config.onPageChange(state.page);
            render();
          }
        });
      if (next)
        next.addEventListener("click", () => {
          if (state.page < totalPages()) {
            state.page++;
            if (config.onPageChange) config.onPageChange(state.page);
            render();
          }
        });
      if (size)
        size.addEventListener("change", () => {
          state.pageSize = Number(size.value);
          state.page = 1;
          render();
        });
    }

    function syncMaster() {
      const master = root.querySelector(".tz-master-checkbox");
      const boxes = Array.from(root.querySelectorAll(".tz-row-checkbox"));
      if (!master) return;
      const checked = boxes.filter((b) => b.checked).length;
      master.checked = checked > 0 && checked === boxes.length;
      master.indeterminate = checked > 0 && checked < boxes.length;
    }

    function publishSelection() {
      const ids = Array.from(state.selection);
      const rows = state.rows.filter((r) => state.selection.has(String(r[config.rowKey])));
      if (config.onSelectionChange) config.onSelectionChange(ids, rows);
      root.dispatchEvent(
        new CustomEvent("tz-table:selection-change", { detail: { ids, rows }, bubbles: true })
      );
    }

    render();

    return {
      root,
      getSelection: () => Array.from(state.selection),
      getSelectedRows: () =>
        state.rows.filter((r) => state.selection.has(String(r[config.rowKey]))),
      setRows: (rows) => {
        state.rows = rows.slice();
        state.page = 1;
        render();
      },
      setActiveRow: (id) => {
        config.activeRowId = id;
        render();
      },
      setPage: (p) => {
        state.page = Math.max(1, Math.min(totalPages(), Number(p) || 1));
        render();
      },
      refresh: render,
      destroy: () => {
        root.innerHTML = "";
      },
    };
  }

  global.TzTable = { mount, version: "0.2.0" };
})(window);
