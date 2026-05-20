// ============================================================================
//  TzTable — reusable, dependency-free, design-system-styled data table.
// ----------------------------------------------------------------------------
//  Bind-mounted to /app/public/tz-table.js inside the container and injected
//  into every HTML response via css_injector.rb. Defines a single global
//  `TzTable` you can call from any page or inline script.
//
//  Usage:
//
//    <div id="my-table"></div>
//    <script>
//      const t = TzTable.mount('#my-table', {
//        columns: [
//          { key: 'login',      label: 'Login' },
//          { key: 'name',       label: 'User Name', type: 'avatar' },
//          { key: 'email',      label: 'Email' },
//          { key: 'admin',      label: 'Administrator', type: 'yesno' },
//          { key: 'created',    label: 'Created at',    type: 'datetime' },
//          { key: 'lastSignIn', label: 'Last sign in',  type: 'datetime' },
//          { key: 'actions',                            type: 'actions' },
//        ],
//        rows: [
//          { id: 1, login: 'Admin',  name: 'Redmine',     email: 'admin@gmail.com',
//            admin: true,  created: '2024-02-15T10:45', lastSignIn: '2026-05-05T13:20' },
//          // ...
//        ],
//        rowKey: 'id',
//        selectable: true,
//        pageSize: 10,
//        actions: [
//          { icon: '⋮', label: 'More', onClick: (row) => console.log(row) },
//        ],
//        onSelectionChange: (ids) => console.log('selected:', ids),
//      });
//      // Later: t.getSelection(), t.setRows(newRows), t.destroy()
//    </script>
//
//  Column types:
//    text       — default; renders `String(row[key])`
//    avatar     — round initial circle + name; uses `row[key]` for the display
//                 text, optional `avatarKey` for initial (defaults to first char)
//    yesno      — green "Yes" when truthy, dim "No" otherwise
//    datetime   — formats ISO/Date as "MM/DD/YYYY | hh:mm AM"
//    date       — formats as "MM/DD/YYYY"
//    badge      — colored pill; `colorKey` chooses the row field to read color from
//    link       — anchor tag; `hrefKey` (or `href` function) for the URL
//    actions    — right-aligned cluster of icon buttons (config.actions[])
//    select     — managed automatically when `selectable: true`; you do not need
//                 to declare it
//    custom     — `render(row)` returns the cell HTML string (use carefully —
//                 you are responsible for escaping)
//
//  Styling: the rendered HTML uses class="tz-table" + .tz-table-container,
//  which are already styled in openproject-custom.css (section 6+). No CSS
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

  const fmtDate = (v) => {
    if (!v) return "";
    const d = v instanceof Date ? v : new Date(v);
    if (isNaN(d)) return escapeHtml(v);
    const mm = String(d.getMonth() + 1).padStart(2, "0");
    const dd = String(d.getDate()).padStart(2, "0");
    return `${mm}/${dd}/${d.getFullYear()}`;
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
        const initial = col.avatarKey
          ? escapeHtml(row[col.avatarKey])
          : escapeHtml(initialOf(v));
        return `<span class="tz-cell-avatar"><span class="tz-avatar" aria-hidden="true">${initial}</span>${escapeHtml(v)}</span>`;
      }
      case "yesno":
        return v
          ? `<span class="tz-cell-yes">Yes</span>`
          : `<span class="tz-cell-no">No</span>`;
      case "date":
        return fmtDate(v);
      case "datetime":
        return fmtDateTime(v);
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
              `<button type="button" class="tz-action-btn" data-tz-action="${i}" aria-label="${escapeHtml(a.label || "")}">${escapeHtml(a.icon || "⋮")}</button>`
          )
          .join("");
      case "custom":
        return typeof col.render === "function" ? col.render(row) : escapeHtml(v);
      default:
        return escapeHtml(v);
    }
  }

  function renderHeaderCell(col) {
    if (col.type === "select") {
      return `<th class="tz-select-cell"><input type="checkbox" class="tz-master-checkbox" aria-label="Select all"></th>`;
    }
    if (col.type === "actions") {
      return `<th class="actions" style="text-align:right">${escapeHtml(col.label || "Actions")}</th>`;
    }
    const sortable = col.sortable === false ? "" : " data-tz-sortable";
    return `<th${sortable} data-tz-key="${escapeHtml(col.key)}">${escapeHtml(col.label || col.key)}</th>`;
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
        onSelectionChange: null,
        onSortChange: null,
        onPageChange: null,
      },
      configIn || {}
    );

    // Inject a leading :select column if requested and not already present
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
      const ctx = { actions: config.actions };

      const headHtml = columns.map(renderHeaderCell).join("");
      const bodyHtml = pageRows.length === 0
        ? `<tr class="tz-table--empty-row"><td colspan="${columns.length}">No data</td></tr>`
        : pageRows
            .map((row) => {
              const id = String(row[config.rowKey]);
              const checked = state.selection.has(id) ? " checked" : "";
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
              return `<tr data-tz-row-id="${escapeHtml(id)}">${cells}</tr>`;
            })
            .join("");

      const footerHtml = state.pageSize
        ? renderFooter(pageRows.length)
        : "";

      root.innerHTML = `
        <div class="tz-table-container">
          <table class="tz-table generic-table">
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
      // master checkbox
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

      // per-row checkboxes
      root.querySelectorAll(".tz-row-checkbox").forEach((el) => {
        el.addEventListener("change", () => {
          if (el.checked) state.selection.add(el.value);
          else state.selection.delete(el.value);
          syncMaster();
          publishSelection();
        });
      });

      // sort headers
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

      // actions
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

      // pagination
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

    // public controller
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

  global.TzTable = { mount, version: "0.1.0" };
})(window);
