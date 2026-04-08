(function() {
    "use strict";

    // ===== Ace Editor Setup =====
    var editor = ace.edit("editor");
    editor.setTheme("ace/theme/" + APP_CONFIG.editorTheme);
    editor.session.setMode("ace/mode/coldfusion");
    editor.setOptions({
        enableBasicAutocompletion: true,
        enableSnippets: true,
        enableLiveAutocompletion: false,
        fontSize: "14px",
        showPrintMargin: false,
        wrap: true
    });
    // Place cursor inside the cfscript block
    editor.gotoLine(2, 0, false);
    editor.focus();

    // ===== DOM References =====
    var engineSelect = document.getElementById("engineSelect");
    var snippetSelect = document.getElementById("snippetSelect");
    var timeoutInput = document.getElementById("timeoutInput");
    var btnRun = document.getElementById("btnRun");
    var btnRunAll = document.getElementById("btnRunAll");
    var btnClearSession = document.getElementById("btnClearSession");
    var statusBar = document.getElementById("statusBar");
    var adminModal = document.getElementById("adminModal");
    var btnCloseModal = document.getElementById("btnCloseModal");
    var serverCards = document.getElementById("serverCards");
    var resultsContainer = document.getElementById("resultsContainer");
    var displayModeToggle = document.getElementById("displayModeToggle");
    var tabBar = document.getElementById("tabBar");

    var currentDisplayMode = "stacked";
    var serverStatuses = {};
    var startingTimers = {};

    // ===== AJAX Helper =====
    function ajax(method, url, data, callback) {
        var xhr = new XMLHttpRequest();
        xhr.open(method, url, true);
        if (method === "POST") {
            xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                var resp;
                try { resp = JSON.parse(xhr.responseText); }
                catch(e) { resp = { success: false, error: xhr.responseText }; }
                callback(resp);
            }
        };
        xhr.send(data || null);
    }

    function encodeParams(obj) {
        var parts = [];
        for (var key in obj) {
            if (obj.hasOwnProperty(key)) {
                parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(obj[key]));
            }
        }
        return parts.join("&");
    }

    // ===== Status Polling =====
    function pollServers() {
        ajax("GET", "api2/servers.cfm", null, function(resp) {
            if (resp.success && resp.servers) {
                serverStatuses = resp.servers;
                renderStatusBar();
                renderEngineDropdown();
                renderServerCards();
            }
        });
    }

    function renderStatusBar() {
        var html = "";
        for (var key in serverStatuses) {
            if (!serverStatuses.hasOwnProperty(key)) continue;
            var s = serverStatuses[key];
            html += '<span class="status-dot ' + s.status + '" title="' + key + ': ' + s.status + '"></span>';
            html += '<span class="status-dot-label">' + key + '</span>';
        }
        statusBar.innerHTML = html;
    }

    function renderEngineDropdown() {
        var current = engineSelect.value;
        var html = '<option value="">-- select --</option>';
        for (var key in serverStatuses) {
            if (!serverStatuses.hasOwnProperty(key)) continue;
            var s = serverStatuses[key];
            if (s.status === "online") {
                var sel = (key === current) ? " selected" : "";
                html += '<option value="' + key + '"' + sel + '>' + key + ' (' + s.cfengine + ')</option>';
            }
        }
        engineSelect.innerHTML = html;
    }

    // ===== Admin Modal =====
    statusBar.addEventListener("click", function() {
        adminModal.classList.add("open");
        renderServerCards();
    });
    btnCloseModal.addEventListener("click", function() {
        adminModal.classList.remove("open");
    });
    adminModal.addEventListener("click", function(e) {
        if (e.target === adminModal) adminModal.classList.remove("open");
    });

    function renderServerCards() {
        var html = "";
        for (var key in serverStatuses) {
            if (!serverStatuses.hasOwnProperty(key)) continue;
            var s = serverStatuses[key];
            html += '<div class="server-card">';
            html += '<span class="server-name">' + key + '</span>';
            html += '<span class="server-engine">' + s.cfengine + '</span>';
            html += '<span class="server-host">' + s.host + ':' + s.port + '</span>';
            html += '<span class="server-status ' + s.status + '">' + s.status;
            if (s.status === "starting" && startingTimers[key]) {
                var elapsed = startingTimers[key].elapsed;
                html += ' <span class="starting-counter">(' + elapsed + 's)</span>';
                if (elapsed >= APP_CONFIG.startupTimeout) {
                    html += ' <span class="starting-warning">Warning: exceeded timeout</span>';
                }
            }
            html += '</span>';

            if (s.status === "offline") {
                html += '<button class="btn-start" data-server="' + key + '">Start</button>';
            } else if (s.status === "online") {
                html += '<button class="btn-stop" data-server="' + key + '">Stop</button>';
            }
            html += '</div>';
        }
        serverCards.innerHTML = html;

        // Bind start/stop buttons
        var startBtns = serverCards.querySelectorAll(".btn-start");
        var stopBtns = serverCards.querySelectorAll(".btn-stop");
        for (var i = 0; i < startBtns.length; i++) {
            startBtns[i].addEventListener("click", handleStart);
        }
        for (var j = 0; j < stopBtns.length; j++) {
            stopBtns[j].addEventListener("click", handleStop);
        }
    }

    function handleStart(e) {
        var serverKey = e.target.getAttribute("data-server");
        ajax("GET", "api2/server-start.cfm?server=" + encodeURIComponent(serverKey), null, function(resp) {
            if (resp.success) {
                // Start a seconds counter
                startingTimers[serverKey] = { elapsed: 0, interval: null };
                startingTimers[serverKey].interval = setInterval(function() {
                    startingTimers[serverKey].elapsed++;
                    renderServerCards();
                    // Check if heartbeat has detected it as online
                    if (serverStatuses[serverKey] && serverStatuses[serverKey].status === "online") {
                        clearInterval(startingTimers[serverKey].interval);
                        delete startingTimers[serverKey];
                        renderServerCards();
                    }
                }, 1000);
                pollServers();
            }
        });
    }

    function handleStop(e) {
        var serverKey = e.target.getAttribute("data-server");
        ajax("GET", "api2/server-stop.cfm?server=" + encodeURIComponent(serverKey), null, function(resp) {
            if (resp.success) pollServers();
        });
    }

    // ===== Code Execution =====
    btnRun.addEventListener("click", function() {
        var engine = engineSelect.value;
        if (!engine) { alert("Please select an engine."); return; }
        executeCode(engine);
    });

    btnRunAll.addEventListener("click", function() {
        executeCode("all");
    });

    function executeCode(engine) {
        // Update timeout config if changed
        var timeout = parseInt(timeoutInput.value, 10) || 0;
        if (timeout !== APP_CONFIG.executionTimeout) {
            APP_CONFIG.executionTimeout = timeout;
            ajax("POST", "api2/config.cfm", encodeParams({ executionTimeout: timeout }), function() {});
        }

        var code = editor.getValue();
        btnRun.disabled = true;
        btnRunAll.disabled = true;
        resultsContainer.innerHTML = '<div style="padding:16px;color:#aaa;">Executing...</div>';

        ajax("POST", "api2/execute.cfm", encodeParams({ code: code, engine: engine }), function(resp) {
            btnRun.disabled = false;
            btnRunAll.disabled = false;
            if (resp.success && resp.results) {
                renderResults(resp.results);
            } else {
                resultsContainer.innerHTML = '<div class="result-card"><div class="result-body error-view">' +
                    escapeHtml(resp.error || "Unknown error") + '</div></div>';
            }
        });
    }

    // ===== Results Rendering =====
    function renderResults(results) {
        if (results.length > 1) {
            displayModeToggle.style.display = "flex";
        } else {
            displayModeToggle.style.display = "none";
        }

        var html = "";
        tabBar.innerHTML = "";

        for (var i = 0; i < results.length; i++) {
            var r = results[i];
            var isActive = (currentDisplayMode === "tabbed" && i === 0) ? " active" : "";
            html += '<div class="result-card' + isActive + '" data-index="' + i + '">';
            html += '<div class="result-header">';
            html += '<span class="engine-name">' + escapeHtml(r.engine) + '</span>';
            html += '<span>' + escapeHtml(r.requestId) + '</span>';
            html += '<span>' + escapeHtml(r.timestamp) + '</span>';
            html += '<span class="duration">' + r.duration + 'ms</span>';

            if (r.success && r.output && hasHtmlTags(r.output)) {
                html += '<button class="btn-source-toggle" data-index="' + i + '">Source</button>';
            }
            html += '</div>';

            if (r.success) {
                html += '<div class="result-body" data-index="' + i + '">' + r.output + '</div>';
            } else {
                var errMsg = r.error;
                if (typeof errMsg === "object") errMsg = errMsg.message || JSON.stringify(errMsg);
                html += '<div class="result-body error-view">' + escapeHtml(errMsg) + '</div>';
            }
            html += '</div>';

            // Tab bar entry
            if (results.length > 1) {
                var tabActive = (i === 0) ? " active" : "";
                tabBar.innerHTML += '<button class="' + tabActive + '" data-index="' + i + '">' + escapeHtml(r.engine) + '</button>';
            }
        }

        resultsContainer.innerHTML = html;
        applyDisplayMode();
        bindResultEvents();
    }

    function hasHtmlTags(str) {
        return /<[a-zA-Z][^>]*>/.test(str);
    }

    function bindResultEvents() {
        // Source toggle buttons
        var toggleBtns = resultsContainer.querySelectorAll(".btn-source-toggle");
        for (var i = 0; i < toggleBtns.length; i++) {
            toggleBtns[i].addEventListener("click", function() {
                var idx = this.getAttribute("data-index");
                var body = resultsContainer.querySelector('.result-body[data-index="' + idx + '"]');
                if (body.classList.contains("source-view")) {
                    body.classList.remove("source-view");
                    body.innerHTML = body.getAttribute("data-html");
                    this.textContent = "Source";
                } else {
                    if (!body.getAttribute("data-html")) {
                        body.setAttribute("data-html", body.innerHTML);
                    }
                    body.classList.add("source-view");
                    body.textContent = body.getAttribute("data-html");
                    this.textContent = "Rendered";
                }
            });
        }

        // Store original HTML for source toggle
        var bodies = resultsContainer.querySelectorAll(".result-body:not(.error-view)");
        for (var j = 0; j < bodies.length; j++) {
            bodies[j].setAttribute("data-html", bodies[j].innerHTML);
        }

        // Tab bar buttons
        var tabBtns = tabBar.querySelectorAll("button");
        for (var k = 0; k < tabBtns.length; k++) {
            tabBtns[k].addEventListener("click", function() {
                var idx = this.getAttribute("data-index");
                // Deactivate all tabs and cards
                var allTabs = tabBar.querySelectorAll("button");
                var allCards = resultsContainer.querySelectorAll(".result-card");
                for (var m = 0; m < allTabs.length; m++) allTabs[m].classList.remove("active");
                for (var n = 0; n < allCards.length; n++) allCards[n].classList.remove("active");
                // Activate selected
                this.classList.add("active");
                var card = resultsContainer.querySelector('.result-card[data-index="' + idx + '"]');
                if (card) card.classList.add("active");
            });
        }
    }

    // ===== Display Mode Toggle =====
    var modeButtons = displayModeToggle.querySelectorAll("button");
    for (var m = 0; m < modeButtons.length; m++) {
        modeButtons[m].addEventListener("click", function() {
            for (var i = 0; i < modeButtons.length; i++) modeButtons[i].classList.remove("active");
            this.classList.add("active");
            currentDisplayMode = this.getAttribute("data-mode");
            applyDisplayMode();
        });
    }

    function applyDisplayMode() {
        resultsContainer.className = "results-container";
        tabBar.style.display = "none";
        if (currentDisplayMode === "side-by-side") {
            resultsContainer.classList.add("side-by-side");
        } else if (currentDisplayMode === "tabbed") {
            resultsContainer.classList.add("tabbed");
            tabBar.style.display = "flex";
        }
    }

    // ===== Snippets =====
    function loadSnippetList() {
        ajax("GET", "api2/snippets.cfm", null, function(resp) {
            if (resp.success && resp.snippets) {
                var html = '<option value="">-- none --</option>';
                for (var i = 0; i < resp.snippets.length; i++) {
                    html += '<option value="' + escapeHtml(resp.snippets[i].name) + '">' +
                        escapeHtml(resp.snippets[i].name) + '</option>';
                }
                snippetSelect.innerHTML = html;
            }
        });
    }

    snippetSelect.addEventListener("change", function() {
        var fileName = this.value;
        if (!fileName) return;
        ajax("GET", "api2/snippet-load.cfm?file=" + encodeURIComponent(fileName), null, function(resp) {
            if (resp.success) {
                editor.setValue(resp.content, -1);
                editor.gotoLine(1, 0, false);
            }
        });
    });

    // ===== Clear Session =====
    btnClearSession.addEventListener("click", function() {
        if (!confirm("Archive current session files and start fresh?")) return;
        ajax("GET", "api2/session-clear.cfm", null, function(resp) {
            if (resp.success) {
                resultsContainer.innerHTML = '<div style="padding:16px;color:#4caf50;">Session cleared and archived.</div>';
            }
        });
    });

    // ===== Timeout Input =====
    timeoutInput.addEventListener("change", function() {
        var val = parseInt(this.value, 10) || 0;
        ajax("POST", "api2/config.cfm", encodeParams({ executionTimeout: val }), function() {});
    });

    // ===== Splitter (drag to resize editor/results) =====
    var splitter = document.getElementById("splitter");
    var editorPanel = document.getElementById("editorPanel");
    var isDragging = false;

    splitter.addEventListener("mousedown", function(e) {
        isDragging = true;
        e.preventDefault();
    });
    document.addEventListener("mousemove", function(e) {
        if (!isDragging) return;
        var newHeight = e.clientY - editorPanel.getBoundingClientRect().top;
        if (newHeight < 100) newHeight = 100;
        editorPanel.style.flex = "none";
        editorPanel.style.height = newHeight + "px";
        editor.resize();
    });
    document.addEventListener("mouseup", function() {
        isDragging = false;
    });

    // ===== Utility =====
    function escapeHtml(str) {
        if (!str) return "";
        var div = document.createElement("div");
        div.appendChild(document.createTextNode(str));
        return div.innerHTML;
    }

    // ===== Initialize =====
    pollServers();
    loadSnippetList();
    setInterval(pollServers, APP_CONFIG.clientPollInterval);

})();
