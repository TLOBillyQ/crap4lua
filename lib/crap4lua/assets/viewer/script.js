(function () {
  /* ── theme toggle ──────────────────────────────────────────── */
  function get_preferred_theme() {
    var stored = null;
    try { stored = localStorage.getItem("crap_theme"); } catch (e) { /* noop */ }
    if (stored === "dark" || stored === "light") {
      return stored;
    }
    if (window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches) {
      return "light";
    }
    return "dark";
  }

  function apply_theme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    var icon = document.querySelector(".theme_toggle_icon");
    var label = document.querySelector(".theme_toggle_label");
    if (icon) { icon.textContent = theme === "dark" ? "\u263E" : "\u2600"; }
    if (label) { label.textContent = theme === "dark" ? "Dark" : "Light"; }
    try { localStorage.setItem("crap_theme", theme); } catch (e) { /* noop */ }
  }

  /* apply immediately to avoid flash */
  apply_theme(get_preferred_theme());

  function by_id(id) {
    return document.getElementById(id);
  }

  function safe_text(value, fallback) {
    if (value === null || value === undefined || value === "") {
      return fallback || "n/a";
    }
    return String(value);
  }

  function safe_number(value) {
    if (typeof value === "number") {
      return value;
    }
    return 0;
  }

  function risk_class(risk_band) {
    return "risk_" + String(risk_band || "low");
  }

  function summarize_lanes(lanes) {
    var list = Array.isArray(lanes) ? lanes : [];
    if (list.length === 0) {
      return {
        text: "No lane data",
        class_name: "",
        note: "No lane execution metadata was provided in this report.",
      };
    }

    var failed_count = 0;
    var total_failures = 0;
    list.forEach(function (lane) {
      if (lane && lane.failed) {
        failed_count += 1;
        total_failures += safe_number(lane.failure_count);
      }
    });

    if (failed_count > 0) {
      return {
        text: "At risk",
        class_name: "status_failed",
        note:
          safe_text(total_failures) +
          " failure(s) across " +
          safe_text(failed_count) +
          " lane(s).",
      };
    }

    return {
      text: "Healthy",
      class_name: "status_passed",
      note: safe_text(list.length) + " lane(s) completed without failures.",
    };
  }

  function risk_band_counts(functions) {
    var counts = { critical: 0, warning: 0, low: 0 };
    (functions || []).forEach(function (fn) {
      var band = fn && fn.risk_band ? fn.risk_band : "low";
      if (counts[band] === undefined) {
        counts[band] = 0;
      }
      counts[band] += 1;
    });
    return counts;
  }

  function find_module(data, source_path) {
    var modules = data.modules || [];
    for (var i = 0; i < modules.length; i += 1) {
      if (modules[i].source_path === source_path) {
        return modules[i];
      }
    }
    return null;
  }

  function sort_functions(list) {
    var items = (list || []).slice();
    items.sort(function (left, right) {
      if (safe_number(left.crap) === safe_number(right.crap)) {
        if (safe_number(left.complexity) === safe_number(right.complexity)) {
          return safe_text(left.name).localeCompare(safe_text(right.name));
        }
        return safe_number(right.complexity) - safe_number(left.complexity);
      }
      return safe_number(right.crap) - safe_number(left.crap);
    });
    return items;
  }

  function sort_modules(list) {
    var items = (list || []).slice();
    items.sort(function (left, right) {
      if (safe_number(left.max_function_crap) === safe_number(right.max_function_crap)) {
        return safe_text(left.source_name).localeCompare(safe_text(right.source_name));
      }
      return safe_number(right.max_function_crap) - safe_number(left.max_function_crap);
    });
    return items;
  }

  function top_module(data) {
    var modules = sort_modules(data.modules || []);
    return modules.length > 0 ? modules[0] : null;
  }

  function top_function(data) {
    var functions = sort_functions(data.functions || []);
    return functions.length > 0 ? functions[0] : null;
  }

  function summarize_source_roots(metadata) {
    var roots = metadata && Array.isArray(metadata.source_roots) ? metadata.source_roots : [];
    if (roots.length === 0) {
      return "the configured source roots";
    }
    return roots.join(", ");
  }

  function render_hero(data) {
    var summary = data.summary || {};
    var metadata = data.metadata || {};
    var lane_info = summarize_lanes(data.lanes);
    var generated = metadata.generated_at
      ? "Generated " + metadata.generated_at
      : "Generated time unavailable";
    var project_name = safe_text(metadata.project_name, "Project");
    var source_roots = summarize_source_roots(metadata);
    var lead_module = top_module(data);
    var lead_function = top_function(data);

    by_id("summary_text").textContent =
      project_name +
      " risk profile across " +
      source_roots +
      ", surfacing where complexity and observed test reach combine into the highest maintenance exposure.";

    by_id("lane_status").textContent = lane_info.text;
    by_id("lane_status").className = "status_badge " + lane_info.class_name;
    by_id("generated_at").textContent = generated + " · Total CRAP " + safe_text(summary.total_crap);

    by_id("hero_tags").innerHTML =
      "<div class='hero_tag " +
      (safe_number(summary.critical_function_count) > 0 ? "risk_critical" : "risk_low") +
      "'>Critical functions " +
      safe_text(summary.critical_function_count || 0) +
      "</div>" +
      "<div class='hero_tag risk_warning'>Lead module " +
      safe_text(lead_module && lead_module.source_name, "n/a") +
      "</div>" +
      "<div class='hero_tag risk_low'>Top function " +
      safe_text(lead_function && lead_function.name, "n/a") +
      "</div>";
  }

  function metric_card(label, value, note, signal, risk) {
    return (
      "<article class='metric_card'" +
      (risk ? " data-risk='" + risk + "'" : "") +
      ">" +
      "<div><p class='metric_label'>" +
      safe_text(label) +
      "</p><div class='metric_value'>" +
      safe_text(value) +
      "</div></div>" +
      "<div class='metric_footer'><div class='metric_note'>" +
      safe_text(note) +
      "</div><div class='filter_badge'>" +
      safe_text(signal, "") +
      "</div></div>" +
      "</article>"
    );
  }

  function render_metrics(data) {
    var summary = data.summary || {};
    var functions = data.functions || [];
    var average_crap = functions.length > 0
      ? (safe_number(summary.total_crap) / functions.length).toFixed(2)
      : "0.00";
    var lead_module = top_module(data);

    by_id("metric_cards").innerHTML =
      metric_card("Modules", summary.module_count || 0, "Distinct source modules analyzed", "Portfolio") +
      metric_card("Functions", summary.function_count || 0, "Functions detected from luac listings", "Inventory") +
      metric_card("Critical Hotspots", summary.critical_function_count || 0, "Above the critical risk threshold", "Action", "critical") +
      metric_card("Average CRAP", average_crap, "Average function-level risk score", "Benchmark", "warning") +
      metric_card(
        "Lead Module",
        lead_module ? lead_module.max_function_crap : "n/a",
        lead_module ? lead_module.source_name : "No module data",
        "Top exposure",
        "warning"
      );
  }

  function render_spotlights(data) {
    var summary = data.summary || {};
    var lead_module = top_module(data);
    var lead_function = top_function(data);
    var lane_info = summarize_lanes(data.lanes);

    by_id("spotlight_cards").innerHTML =
      "<article class='spotlight_card'><p class='panel_eyebrow'>Highest Exposure</p><div class='spotlight_title'>" +
      safe_text(lead_function && lead_function.name, "n/a") +
      "</div><div class='spotlight_note'>" +
      safe_text(lead_function && lead_function.source_path, "No hotspot data") +
      "</div><div class='spotlight_value'>" +
      safe_text(lead_function && lead_function.crap, "n/a") +
      "</div></article>" +
      "<article class='spotlight_card'><p class='panel_eyebrow'>Primary Module</p><div class='spotlight_title'>" +
      safe_text(lead_module && lead_module.source_name, "n/a") +
      "</div><div class='spotlight_note'>Module max CRAP · hit lines " +
      safe_text(lead_module && lead_module.hit_line_count, "n/a") +
      "</div><div class='spotlight_value'>" +
      safe_text(lead_module && lead_module.max_function_crap, "n/a") +
      "</div></article>" +
      "<article class='spotlight_card'><p class='panel_eyebrow'>Execution Posture</p><div class='spotlight_title'>" +
      safe_text(lane_info.text) +
      "</div><div class='spotlight_note'>" +
      safe_text(lane_info.note) +
      "</div><div class='spotlight_value'>" +
      safe_text(summary.total_crap || 0) +
      "</div></article>";
  }

  function distribution_row(label, count, total, class_name) {
    var percent = total > 0 ? Math.round((count / total) * 100) : 0;
    return (
      "<div class='distribution_row'>" +
      "<div class='distribution_meta'><div><div class='distribution_label'>" +
      safe_text(label) +
      "</div><div class='distribution_value'>" +
      safe_text(count) +
      "</div></div><div class='risk_pill " +
      class_name +
      "'>" +
      safe_text(percent) +
      "%</div></div>" +
      "<div class='distribution_bar'><div class='distribution_bar_fill " +
      class_name +
      "' style='width:" +
      safe_text(percent) +
      "%'></div></div>" +
      "</div>"
    );
  }

  function render_distribution(data) {
    var functions = data.functions || [];
    var counts = risk_band_counts(functions);
    var total = functions.length;
    by_id("risk_distribution").innerHTML =
      distribution_row("Critical", counts.critical || 0, total, "risk_critical") +
      distribution_row("Warning", counts.warning || 0, total, "risk_warning") +
      distribution_row("Low", counts.low || 0, total, "risk_low");
  }

  function render_agenda(data) {
    var functions = sort_functions(data.functions || []).slice(0, 3);
    by_id("agenda_list").innerHTML = functions.map(function (fn, index) {
      var module_data = find_module(data, fn.source_path);
      var focus = safe_number(fn.coverage) <= 0.1
        ? "Raise coverage before structural changes."
        : "Refactor branching and isolate decision flow.";
      return (
        "<article class='agenda_card'>" +
        "<p class='panel_eyebrow'>Agenda " +
        safe_text(index + 1) +
        "</p><div class='agenda_title'>" +
        safe_text(fn.name) +
        "</div><div class='agenda_note'>" +
        safe_text(fn.source_path) +
        "<br>" +
        focus +
        "</div><div class='agenda_value'>CRAP " +
        safe_text(fn.crap) +
        "</div><div class='detail_footer'>" +
        "<div class='filter_badge'>Coverage " +
        safe_text(fn.coverage) +
        "</div><div class='filter_badge'>Module " +
        safe_text(module_data && module_data.source_name, "n/a") +
        "</div></div></article>"
      );
    }).join("");
  }

  function details_markup(fn, module_data) {
    if (!fn) {
      return "<div class='details_empty'>Select a function to inspect its metrics.</div>";
    }

    return (
      "<div class='detail_title_row'>" +
      "<div><div class='function_name'>" +
      safe_text(fn.name) +
      "</div><div class='detail_meta'>" +
      safe_text(fn.source_path) +
      ":" +
      safe_text(fn.start_line) +
      "-" +
      safe_text(fn.end_line) +
      "</div></div>" +
      "<div class='risk_pill " +
      risk_class(fn.risk_band) +
      "'>" +
      safe_text(fn.risk_band, "low") +
      "</div></div>" +
      "<div class='detail_stats'>" +
      "<div class='detail_stat'><div class='stat_label'>CRAP</div><div class='stat_value'>" +
      safe_text(fn.crap) +
      "</div></div>" +
      "<div class='detail_stat'><div class='stat_label'>Complexity</div><div class='stat_value'>" +
      safe_text(fn.complexity) +
      "</div></div>" +
      "<div class='detail_stat'><div class='stat_label'>Coverage</div><div class='stat_value'>" +
      safe_text(fn.coverage) +
      "</div></div>" +
      "<div class='detail_stat'><div class='stat_label'>Decision Lines</div><div class='stat_value'>" +
      safe_text(fn.decision_line_count) +
      "</div></div>" +
      "<div class='detail_stat'><div class='stat_label'>Executable Lines</div><div class='stat_value'>" +
      safe_text(fn.executable_line_count) +
      "</div></div>" +
      "<div class='detail_stat'><div class='stat_label'>Hit Lines</div><div class='stat_value'>" +
      safe_text(fn.hit_line_count) +
      "</div></div>" +
      "</div>" +
      "<div class='detail_footer'>" +
      "<div class='filter_badge'>Module " +
      safe_text(fn.source_name) +
      "</div>" +
      "<div class='filter_badge'>Module max CRAP " +
      safe_text(module_data && module_data.max_function_crap) +
      "</div>" +
      "<div class='filter_badge'>Module functions " +
      safe_text(module_data && module_data.function_count) +
      "</div>" +
      "</div>"
    );
  }

  function render_details(data, fn) {
    by_id("details_card").innerHTML = details_markup(
      fn,
      fn ? find_module(data, fn.source_path) : null
    );
  }

  function render_functions(data, state) {
    var container = by_id("function_rows");
    var functions = sort_functions((data.functions || []).filter(function (fn) {
      if (!state.active_module) {
        return true;
      }
      return fn.source_path === state.active_module;
    }));

    by_id("active_filter").textContent = state.active_module
      ? "Filtered by " + state.active_module
      : "All modules";
    by_id("function_results").textContent =
      "Showing " + safe_text(functions.length) + " matching functions";

    if (!state.selected_function_id || !functions.some(function (fn) {
      return fn.id === state.selected_function_id;
    })) {
      state.selected_function_id = functions[0] ? functions[0].id : null;
    }

    container.innerHTML = "";
    functions.forEach(function (fn, index) {
      var card = document.createElement("button");
      var selected = state.selected_function_id === fn.id;
      card.className = "function_card" + (selected ? " is_active" : "");
      card.innerHTML =
        "<div class='function_head'>" +
        "<div><div class='function_name'>" +
        safe_text(index + 1) +
        ". " +
        safe_text(fn.name) +
        "</div><div class='function_path'>" +
        safe_text(fn.source_path) +
        ":" +
        safe_text(fn.start_line) +
        "</div></div>" +
        "<div class='risk_pill " +
        risk_class(fn.risk_band) +
        "'>" +
        safe_text(fn.crap) +
        "</div></div>" +
        "<div class='function_stats'>" +
        "<div class='stat_block'><div class='stat_label'>Complexity</div><div class='stat_value'>" +
        safe_text(fn.complexity) +
        "</div></div>" +
        "<div class='stat_block'><div class='stat_label'>Coverage</div><div class='stat_value'>" +
        safe_text(fn.coverage) +
        "</div></div>" +
        "<div class='stat_block'><div class='stat_label'>Hit / Exec</div><div class='stat_value'>" +
        safe_text(fn.hit_line_count) +
        " / " +
        safe_text(fn.executable_line_count) +
        "</div></div>" +
        "</div>";
      card.addEventListener("click", function () {
        state.selected_function_id = fn.id;
        render_functions(data, state);
        render_details(data, fn);
      });
      container.appendChild(card);
    });

    render_details(
      data,
      functions.find(function (fn) {
        return fn.id === state.selected_function_id;
      }) || null
    );
  }

  function module_risk_class(value) {
    var numeric = safe_number(value);
    if (numeric > 30) {
      return "risk_critical";
    }
    if (numeric >= 10) {
      return "risk_warning";
    }
    return "risk_low";
  }

  function render_modules(data, state) {
    var container = by_id("module_list");
    var modules = sort_modules(data.modules || []);
    container.innerHTML = "";
    by_id("module_results").textContent =
      "Showing " + safe_text(modules.length) + " modules";

    var reset = document.createElement("button");
    reset.className = "module_card" + (!state.active_module ? " is_active" : "");
    reset.innerHTML =
      "<div class='module_head'><div><div class='module_name'>All Modules</div><div class='module_path'>Reset the current module filter</div></div><div class='filter_badge'>Portfolio</div></div>";
    reset.addEventListener("click", function () {
      state.active_module = null;
      state.selected_function_id = null;
      render_modules(data, state);
      render_functions(data, state);
    });
    container.appendChild(reset);

    modules.forEach(function (mod) {
      var selected = state.active_module === mod.source_path;
      var card = document.createElement("button");
      card.className = "module_card" + (selected ? " is_active" : "");
      card.innerHTML =
        "<div class='module_head'><div><div class='module_name'>" +
        safe_text(mod.source_name) +
        "</div><div class='module_path'>" +
        safe_text(mod.source_path) +
        "</div></div><div class='risk_pill " +
        module_risk_class(mod.max_function_crap) +
        "'>" +
        safe_text(mod.max_function_crap) +
        "</div></div>" +
        "<div class='module_stats'>" +
        "<div class='stat_block'><div class='stat_label'>Functions</div><div class='stat_value'>" +
        safe_text(mod.function_count) +
        "</div></div>" +
        "<div class='stat_block'><div class='stat_label'>Hit Lines</div><div class='stat_value'>" +
        safe_text(mod.hit_line_count) +
        "</div></div>" +
        "</div>";
      card.addEventListener("click", function () {
        state.active_module = selected ? null : mod.source_path;
        state.selected_function_id = null;
        render_modules(data, state);
        render_functions(data, state);
      });
      container.appendChild(card);
    });
  }

  function render_all(data, state) {
    render_hero(data);
    render_metrics(data);
    render_spotlights(data);
    render_distribution(data);
    render_agenda(data);
    render_modules(data, state);
    render_functions(data, state);
  }

  document.addEventListener("DOMContentLoaded", function () {
    var data = window.CRAP_REPORT_DATA;
    if (!data) {
      by_id("summary_text").textContent =
        "Missing window.CRAP_REPORT_DATA. Generate viewer assets first.";
      return;
    }

    var state = {
      active_module: null,
      selected_function_id: data.functions && data.functions[0] ? data.functions[0].id : null,
    };

    render_all(data, state);

    /* wire theme toggle */
    var toggle = by_id("theme_toggle");
    if (toggle) {
      toggle.addEventListener("click", function () {
        var current = document.documentElement.getAttribute("data-theme") || "dark";
        apply_theme(current === "dark" ? "light" : "dark");
      });
    }
  });
})();
