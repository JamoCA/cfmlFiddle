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
	// Set default content: empty cfscript block
	editor.setValue("<cfscript>\n\n</cfscript>", -1);
	// Place cursor inside the cfscript block
	editor.gotoLine(2, 0, false);
	editor.focus();

	// ===== DOM References =====
	var engineSelect = document.getElementById("engineSelect");
	var snippetSelect = document.getElementById("snippetSelect");
	var timeoutInput = document.getElementById("timeoutInput");
	var btnRun = document.getElementById("btnRun");
	var btnRunAll = document.getElementById("btnRunAll");
	var btnSession = document.getElementById("btnSession");
	var btnReinit = document.getElementById("btnReinit");
	var btnSaveSnippet = document.getElementById("btnSaveSnippet");
	var btnImportGist = document.getElementById("btnImportGist");
	var chkAppend = document.getElementById("chkAppend");
	var chkInteractive = document.getElementById("chkInteractive");
	var chkShowConsole = document.getElementById("chkShowConsole");
	var btnClearResults = document.getElementById("btnClearResults");
	var statusBar = document.getElementById("statusBar");
	var adminModal = document.getElementById("adminModal");
	var btnCloseModal = document.getElementById("btnCloseModal");
	var serverCards = document.getElementById("serverCards");
	var resultsContainer = document.getElementById("resultsContainer");
	var displayModeToggle = document.getElementById("displayModeToggle");
	var tabBar = document.getElementById("tabBar");

	var currentDisplayMode = "stacked";
	var serverStatuses = {};
	var hostServerKey = "";
	var startingTimers = {};
	var resultGroupCounter = 0;

	// ===== Theme Toggle =====
	var btnTheme = document.getElementById("btnTheme");

	function getTheme() {
		return document.documentElement.getAttribute("data-theme") || "dark";
	}

	function setTheme(theme) {
		document.documentElement.setAttribute("data-theme", theme);
		localStorage.setItem("cfmlfiddle-theme", theme);
		btnTheme.innerHTML = theme === "dark" ? "&#x263E;" : "&#x2600;";
		btnTheme.title = theme === "dark" ? "Switch to light theme" : "Switch to dark theme";
		// Update Ace editor theme to match
		editor.setTheme(theme === "dark" ? "ace/theme/monokai" : "ace/theme/chrome");
	}

	btnTheme.addEventListener("click", function() {
		setTheme(getTheme() === "dark" ? "light" : "dark");
	});

	// Apply initial icon state
	setTheme(getTheme());

	// ===== Keyboard: Status Bar =====
	statusBar.addEventListener("keydown", function(e) {
		if (e.key === "Enter" || e.key === " ") {
			e.preventDefault();
			statusBar.click();
		}
	});

	// ===== Keyboard: Splitter =====
	var splitter = document.getElementById("splitter");
	var editorPanel = document.getElementById("editorPanel");

	splitter.addEventListener("keydown", function(e) {
		var step = e.shiftKey ? 50 : 10;
		if (e.key === "ArrowUp" || e.key === "ArrowDown") {
			e.preventDefault();
			var currentHeight = editorPanel.getBoundingClientRect().height;
			var newHeight = e.key === "ArrowUp" ? currentHeight - step : currentHeight + step;
			if (newHeight < 100) newHeight = 100;
			editorPanel.style.flex = "none";
			editorPanel.style.height = newHeight + "px";
			editor.resize();
		}
	});

	// ===== SweetAlert2 Theme Helper =====
	function swalFire(opts) {
		var isDark = getTheme() === "dark";
		var defaults = {
			background: isDark ? "#2d2d2d" : "#ffffff",
			color: isDark ? "#d4d4d4" : "#1e1e1e"
		};
		for (var k in opts) {
			if (opts.hasOwnProperty(k)) defaults[k] = opts[k];
		}
		return Swal.fire(defaults);
	}

	// ===== AJAX Helper =====
	function ajax(method, url, data, callback) {
		var opts = { method: method };
		if (method === "POST" && data) {
			opts.headers = { "Content-Type": "application/x-www-form-urlencoded" };
			opts.body = data;
		}
		fetch(url, opts)
			.then(function(r) { return r.text(); })
			.then(function(text) {
				var resp;
				try { resp = JSON.parse(text); }
				catch(e) { resp = { success: false, error: text }; }
				callback(resp);
			})
			.catch(function() {
				callback({ success: false, error: "Network error" });
			});
	}

	function encodeParams(obj) {
		return new URLSearchParams(obj).toString();
	}

	// ===== Status Updates (shared handler for polling and SSE) =====
	function handleServerUpdate(resp) {
		if (isTrue(resp.success) && resp.servers) {
			serverStatuses = resp.servers;
			if (resp.hostServer) {
				hostServerKey = resp.hostServer;
				var hostStatus = serverStatuses[hostServerKey];
				var titleUptime = (hostStatus && hostStatus.onlineSince) ? " (" + formatUptime(hostStatus.onlineSince) + ")" : "";
				document.title = "CFMLFiddle - " + hostServerKey + titleUptime;
			}
			updatePayloadCount(resp.payloadCount);
			renderStatusBar();
			renderEngineDropdown();
			renderServerCards();
		}
	}

	// ===== Polling =====
	var pollTimer = null;

	function pollServers() {
		ajax("GET", "api2/servers.cfm", null, function(resp) {
			handleServerUpdate(resp);
		});
	}

	function startPolling() {
		pollServers();
		if (pollTimer) clearInterval(pollTimer);
		pollTimer = setInterval(pollServers, APP_CONFIG.clientPollInterval);
	}

	function stopPolling() {
		if (pollTimer) {
			clearInterval(pollTimer);
			pollTimer = null;
		}
	}

	// ===== Server-Sent Events =====
	var eventSource = null;

	function startSSE() {
		if (!window.EventSource) {
			// Browser doesn't support SSE, fall back to polling
			startPolling();
			return;
		}

		// Do an initial poll to get data immediately (SSE may take a few seconds)
		pollServers();

		eventSource = new EventSource("api2/server-events.cfm");

		eventSource.onmessage = function(e) {
			try {
				var resp = JSON.parse(e.data);
				handleServerUpdate(resp);
			} catch(err) {}
		};

		eventSource.onerror = function() {
			// SSE failed — close and fall back to polling
			if (eventSource) {
				eventSource.close();
				eventSource = null;
			}
			startPolling();
		};
	}

	function renderStatusBar() {
		var html = "";
		for (var key in serverStatuses) {
			if (!serverStatuses.hasOwnProperty(key)) continue;
			var s = serverStatuses[key];
			html += '<span class="status-btn ' + s.status + '" title="' + key + ': ' + s.status + '">' + key + '</span>';
		}
		statusBar.innerHTML = html;
	}

	function renderEngineDropdown() {
		var current = engineSelect.value;
		var onlineKeys = [];
		for (var key in serverStatuses) {
			if (serverStatuses.hasOwnProperty(key) && serverStatuses[key].status === "online") {
				onlineKeys.push(key);
			}
		}

		// Auto-select if only one engine is online and none currently selected
		if (onlineKeys.length === 1 && !current) {
			current = onlineKeys[0];
		}

		var html = '<option value="">-- select --</option>';
		for (var i = 0; i < onlineKeys.length; i++) {
			var k = onlineKeys[i];
			var s = serverStatuses[k];
			var sel = (k === current) ? " selected" : "";
			var label = k + ' (' + s.cfengine + (s.productVersion ? ' ' + s.productVersion : '') + ')';
			html += '<option value="' + k + '"' + sel + '>' + label + '</option>';
		}
		engineSelect.innerHTML = html;
	}

	// ===== About Modal =====
	var aboutModal = document.getElementById("aboutModal");
	var btnAbout = document.getElementById("btnAbout");
	var btnCloseAbout = document.getElementById("btnCloseAbout");
	btnAbout.addEventListener("click", function() {
		aboutModal.showModal();
	});
	btnCloseAbout.addEventListener("click", function() {
		aboutModal.close();
	});
	aboutModal.addEventListener("click", function(e) {
		if (e.target === aboutModal) aboutModal.close();
	});

	// ===== Admin Modal =====
	statusBar.addEventListener("click", function() {
		adminModal.showModal();
		renderServerCards();
	});
	btnCloseModal.addEventListener("click", function() {
		adminModal.close();
	});
	adminModal.addEventListener("click", function(e) {
		if (e.target === adminModal) adminModal.close();
	});

	function countOnlineServers() {
		var count = 0;
		for (var key in serverStatuses) {
			if (serverStatuses.hasOwnProperty(key) && serverStatuses[key].status === "online") count++;
		}
		return count;
	}

	// Engine metadata for context menus
	var engineMeta = {
		"adobe": {
			adminPath: "/CFIDE/administrator/index.cfm",
			docsUrl: "https://helpx.adobe.com/coldfusion/user-guide.html",
			homeUrl: "https://coldfusion.adobe.com/"
		},
		"lucee": {
			adminPath: "/lucee/admin/web.cfm",
			docsUrl: "https://docs.lucee.org/",
			homeUrl: "https://www.lucee.org/"
		},
		"boxlang": {
			adminPath: "/bx/",
			docsUrl: "https://boxlang.ortusbooks.com/",
			homeUrl: "https://boxlang.io/"
		}
	};

	function getEnginePlatform(cfengine) {
		if (!cfengine) return "adobe";
		var e = cfengine.toLowerCase();
		if (e.indexOf("lucee") !== -1) return "lucee";
		if (e.indexOf("boxlang") !== -1) return "boxlang";
		return "adobe";
	}

	function renderServerCards() {
		var html = "";
		var onlineCount = countOnlineServers();

		for (var key in serverStatuses) {
			if (!serverStatuses.hasOwnProperty(key)) continue;
			var s = serverStatuses[key];
			var isHost = (key === hostServerKey);
			var versionText = s.productVersion ? escapeHtml(s.productVersion) : "";

			html += '<div class="server-card context-server" data-server="' + key + '">';
			html += '<span class="server-name">' + key + (isHost ? ' <span class="host-badge">host</span>' : '') + '</span>';
			html += '<span class="server-engine">' + s.cfengine + '</span>';
			if (versionText) {
				html += '<span class="server-version">' + versionText + '</span>';
			}
			html += '<span class="server-status ' + s.status + '">' + s.status;
			if (s.status === "starting" && startingTimers[key]) {
				var elapsed = startingTimers[key].elapsed;
				html += ' <span class="starting-counter">(' + elapsed + 's)</span>';
				if (elapsed >= APP_CONFIG.startupTimeout) {
					html += ' <span class="starting-warning">Warning: exceeded timeout</span>';
				}
			}
			html += '</span>';
			html += '</div>';
		}

		// Stop All button (only when 2+ servers are online)
		if (onlineCount >= 2) {
			html += '<div class="server-card stop-all-card">';
			html += '<button class="btn-stop-all" id="btnStopAll">Stop All</button>';
			html += '</div>';
		}

		serverCards.innerHTML = html;

		// Bind Stop All
		var btnStopAll = document.getElementById("btnStopAll");
		if (btnStopAll) {
			btnStopAll.addEventListener("click", handleStopAll);
		}

		// Initialize context menus for each server card
		initServerContextMenus();
	}

	function initServerContextMenus() {
		// Destroy existing context menus to avoid duplicates
		try { $.contextMenu("destroy", "#adminModal .context-server"); } catch(e) {}

		var onlineCount = countOnlineServers();

		$.contextMenu({
			selector: "#adminModal .context-server",
			appendTo: "#adminModal",
			trigger: "left",
			build: function($trigger) {
				var key = $trigger.attr("data-server");
				var s = serverStatuses[key];
				if (!s) return false;

				var isHost = (key === hostServerKey);
				var platform = getEnginePlatform(s.cfengine);
				var meta = engineMeta[platform];
				var baseUrl = "http://localhost:" + s.port;
				var items = {};

				// Info header (disabled, just for display)
				var infoLabel = s.cfengine;
				if (s.productVersion) infoLabel += " " + s.productVersion;
				if (s.productName) infoLabel = s.productName + " " + (s.productVersion || "");
				items["info"] = { name: infoLabel, disabled: true, className: "context-info" };
				if (s.onlineSince) {
					items["uptime"] = { name: "Uptime: " + formatUptime(s.onlineSince), disabled: true, className: "context-detail" };
				}
				items["sep1"] = "---";

				// Actions
				if (s.status === "offline") {
					items["start"] = {
						name: "Start Server",
						callback: function() { triggerStart(key); }
					};
				} else if (s.status === "online") {
					if (isHost && onlineCount > 1) {
						items["stop"] = { name: "Stop Server (stop others first)", disabled: true };
					} else {
						items["stop"] = {
							name: "Stop Server",
							callback: function() { triggerStop(key); }
						};
					}
				} else {
					items["pending"] = { name: s.status + "\u2026", disabled: true };
				}

				// Links (only when online)
				if (s.status === "online") {
					items["sep2"] = "---";
					items["open"] = {
						name: "Open Homepage",
						callback: function() { window.open(baseUrl + "/", "_blank"); }
					};
					items["admin"] = {
						name: "Open Admin",
						callback: function() { window.open(baseUrl + meta.adminPath, "_blank"); }
					};
				}

				// External links
				items["sep3"] = "---";
				items["docs"] = {
					name: "Documentation",
					callback: function() { window.open(meta.docsUrl, "_blank"); }
				};
				items["home"] = {
					name: "Project Website",
					callback: function() { window.open(meta.homeUrl, "_blank"); }
				};

				return { items: items };
			},
			position: function(opt, x, y) {
				// Convert viewport coords to modal-relative coords
				var modal = document.getElementById("adminModal");
				var modalRect = modal.getBoundingClientRect();
				var relX = x - modalRect.left + modal.scrollLeft;
				var relY = y - modalRect.top + modal.scrollTop;
				var menuWidth = opt.$menu.outerWidth();
				var modalInnerWidth = modal.clientWidth;
				// Clamp so menu stays within the modal
				if (relX + menuWidth > modalInnerWidth - 8) {
					relX = modalInnerWidth - menuWidth - 8;
				}
				if (relX < 8) relX = 8;
				opt.$menu.css({ top: relY, left: relX, position: "absolute" });
			}
		});
	}

	function triggerStart(serverKey) {
		if (serverStatuses[serverKey]) serverStatuses[serverKey].status = "starting";
		renderStatusBar();
		renderServerCards();
		var showConsole = chkShowConsole.checked ? "&showConsole=1" : "";
		ajax("GET", "api2/server-start.cfm?server=" + encodeURIComponent(serverKey) + showConsole, null, function(resp) {
			if (isTrue(resp.success)) {
				startingTimers[serverKey] = { elapsed: 0, interval: null };
				startingTimers[serverKey].interval = setInterval(function() {
					startingTimers[serverKey].elapsed++;
					renderServerCards();
					if (serverStatuses[serverKey] && serverStatuses[serverKey].status === "online") {
						clearInterval(startingTimers[serverKey].interval);
						delete startingTimers[serverKey];
						renderServerCards();
					}
				}, 1000);
				pollServers();
			} else {
				renderServerCards();
			}
		});
	}

	function triggerStop(serverKey) {
		if (serverStatuses[serverKey]) serverStatuses[serverKey].status = "stopping";
		renderStatusBar();
		renderServerCards();
		ajax("GET", "api2/server-stop.cfm?server=" + encodeURIComponent(serverKey), null, function(resp) {
			if (isTrue(resp.success)) pollServers();
			else renderServerCards();
		});
	}

	function handleStopAll() {
		swalFire({
			title: "Stop All Servers?",
			text: "The host server will be stopped last.",
			icon: "warning",
			showCancelButton: true,
			confirmButtonColor: "#c62828",
			confirmButtonText: "Stop All",
		}).then(function(result) {
			if (!result.isConfirmed) return;
			doStopAll();
		});
	}

	function doStopAll() {
		// Collect online non-host servers, then host last
		var nonHost = [];
		for (var key in serverStatuses) {
			if (!serverStatuses.hasOwnProperty(key)) continue;
			if (serverStatuses[key].status === "online" && key !== hostServerKey) {
				nonHost.push(key);
			}
		}
		// Add host at the end
		if (hostServerKey && serverStatuses[hostServerKey] && serverStatuses[hostServerKey].status === "online") {
			nonHost.push(hostServerKey);
		}

		// Stop sequentially: wait for each request before sending the next
		function stopNext(index) {
			if (index >= nonHost.length) {
				pollServers();
				return;
			}
			ajax("GET", "api2/server-stop.cfm?server=" + encodeURIComponent(nonHost[index]), null, function() {
				stopNext(index + 1);
			});
		}
		stopNext(0);
	}

	// ===== Code Execution =====
	btnRun.addEventListener("click", function() {
		var engine = engineSelect.value;
		if (!engine) { swalFire({ icon: "warning", title: "No Engine", text: "Please select an engine."}); return; }
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
		var isAppend = chkAppend.checked;
		btnRun.disabled = true;
		btnRunAll.disabled = true;

		if (!isAppend) {
			resultsContainer.innerHTML = '<div style="padding:16px;color:#aaa;">Executing...</div>';
		}

		ajax("POST", "api2/execute.cfm", encodeParams({ code: code, engine: engine }), function(resp) {
			btnRun.disabled = false;
			btnRunAll.disabled = false;
			if (resp.payloadCount !== undefined) updatePayloadCount(resp.payloadCount);
			if (isTrue(resp.success) && resp.results) {
				renderResults(resp.results, isAppend);
			} else if (resp.error === "BINARY_CONTENT") {
				swalFire({
					icon: "error",
					title: "Invalid Content",
					text: "The payload contains binary or non-text content and cannot be executed.",
				});
			} else {
				var errorHtml = '<div class="result-card"><div class="result-body error-view">' +
					escapeHtml(resp.error || "Unknown error") + '</div></div>';
				if (isAppend) {
					appendResultGroup(errorHtml);
				} else {
					resultsContainer.innerHTML = errorHtml;
				}
			}
			updateClearAllButton();
		});
	}

	// ===== Results Rendering =====
	// Detect if output needs interactive mode (forms with no/relative action, relative links)
	function needsInteractive(output) {
		if (!output) return false;
		// Form with no action, empty action, or relative action (no http)
		if (/<form\b/i.test(output)) {
			// Form without action attribute, or action="" or action="something-relative"
			if (/<form\b(?![^>]*action\s*=)/i.test(output)) return true;
			if (/<form\b[^>]*action\s*=\s*["']\s*["']/i.test(output)) return true;
			if (/<form\b[^>]*action\s*=\s*["'](?!https?:\/\/)/i.test(output)) return true;
		}
		return false;
	}

	function buildResultCardsHtml(results, groupId) {
		var forceInteractive = chkInteractive.checked;
		var html = "";
		for (var i = 0; i < results.length; i++) {
			var r = results[i];
			var cardIdx = groupId + "-" + i;
			var isActive = (currentDisplayMode === "tabbed" && i === 0) ? " active" : "";
			var isError = !isTrue(r.success) ? " error" : "";
			var useIframe = isTrue(r.success) && r.interactiveURL && (forceInteractive || needsInteractive(r.output));

			html += '<div class="result-card' + isActive + isError + '" data-index="' + cardIdx + '">';
			html += '<div class="result-header">';
			html += '<span class="engine-name">' + escapeHtml(r.engine) + '</span>';
			html += '<span>' + escapeHtml(r.requestId) + '</span>';
			html += '<span>' + escapeHtml(r.timestamp) + '</span>';
			html += '<span class="duration">' + r.duration + 'ms</span>';

			var dismissBtn = '<button class="btn-dismiss-card" data-index="' + cardIdx + '" title="Dismiss this result">&times;</button>';

			if (isTrue(r.success)) {
				if (useIframe) {
					html += '<span class="result-mode interactive">interactive</span>';
					if (r.payloadFile) {
						html += '<button class="btn-refresh" data-index="' + cardIdx + '" data-payload="' + escapeHtml(r.payloadFile) + '" data-engine="' + escapeHtml(r.engine) + '" title="Re-execute this result">&#x21bb;</button>';
					}
					html += dismissBtn;
					html += '</div>';
					html += '<iframe class="result-iframe" data-index="' + cardIdx + '" data-src="' + escapeHtml(r.interactiveURL) + '" src="' + escapeHtml(r.interactiveURL) + '" sandbox="allow-forms allow-scripts allow-same-origin"></iframe>';
				} else {
					html += '<span class="result-mode static">static</span>';
					if (r.payloadFile) {
						html += '<button class="btn-refresh" data-index="' + cardIdx + '" data-payload="' + escapeHtml(r.payloadFile) + '" data-engine="' + escapeHtml(r.engine) + '" title="Re-execute this result">&#x21bb;</button>';
					}
					if (r.output && hasHtmlTags(r.output)) {
						html += '<button class="btn-source-toggle" data-index="' + cardIdx + '">Source</button>';
					}
					html += dismissBtn;
					html += '</div>';
					html += '<div class="result-body" data-index="' + cardIdx + '">' + r.output + '</div>';
				}
			} else {
				var errObj = r.error;
				var rawHtml = (typeof errObj === "object") ? getField(errObj, "raw") : null;
				var errMsg = (typeof errObj === "object") ? (getField(errObj, "message") || JSON.stringify(errObj)) : String(errObj || "Unknown error");
				var statusCode = (typeof errObj === "object") ? getField(errObj, "statusCode") : "";
				if (statusCode) {
					html += '<span class="error-status">HTTP ' + escapeHtml(String(statusCode)) + '</span>';
				}
				if (rawHtml && hasHtmlTags(rawHtml)) {
					html += '<button class="btn-source-toggle" data-index="' + cardIdx + '">Source</button>';
				}
				html += dismissBtn;
				html += '</div>';
				if (rawHtml && hasHtmlTags(rawHtml)) {
					// Render the CF error page as HTML so stack traces are readable
					html += '<div class="result-body error-rendered" data-index="' + cardIdx + '">' + rawHtml + '</div>';
				} else {
					html += '<div class="result-body error-view" data-index="' + cardIdx + '">' + escapeHtml(errMsg) + '</div>';
				}
			}
			html += '</div>';
		}
		return html;
	}

	function renderResults(results, isAppend) {
		var groupId = ++resultGroupCounter;
		var cardsHtml = buildResultCardsHtml(results, groupId);

		if (isAppend) {
			appendResultGroup(cardsHtml);
			// Hide display mode toggle in append mode (stacked only)
			displayModeToggle.classList.add("hidden");
			tabBar.innerHTML = "";
		} else {
			if (results.length > 1) {
				displayModeToggle.classList.remove("hidden");
			} else {
				displayModeToggle.classList.add("hidden");
			}
			tabBar.innerHTML = "";
			resultsContainer.innerHTML = cardsHtml;

			// Build tab bar for non-append multi-result
			if (results.length > 1) {
				for (var i = 0; i < results.length; i++) {
					var tabActive = (i === 0) ? " active" : "";
					tabBar.innerHTML += '<button class="' + tabActive + '" data-index="' + groupId + '-' + i + '">' + escapeHtml(results[i].engine) + '</button>';
				}
			}
			applyDisplayMode();
		}
		bindResultEvents();
	}

	function wrapExistingResults() {
		// If there's loose content (not in a result-group), wrap it so it can be dismissed
		if (resultsContainer.children.length > 0 && !resultsContainer.querySelector(".result-group")) {
			var prevGroup = document.createElement("div");
			prevGroup.className = "result-group";
			prevGroup.setAttribute("data-group", "0");

			var header = '<div class="result-group-header">';
			header += '<span class="group-timestamp">Previous result</span>';
			header += '<button class="btn-dismiss-group" data-group="0" title="Dismiss this result">&times;</button>';
			header += '</div>';

			var existing = "";
			while (resultsContainer.firstChild) {
				var child = resultsContainer.firstChild;
				resultsContainer.removeChild(child);
				if (child.outerHTML) existing += child.outerHTML;
			}
			prevGroup.innerHTML = header + existing;
			resultsContainer.appendChild(prevGroup);

			var dismissBtn = prevGroup.querySelector(".btn-dismiss-group");
			dismissBtn.addEventListener("click", function() {
				prevGroup.parentNode.removeChild(prevGroup);
				updateClearAllButton();
			});
		}
	}

	function appendResultGroup(contentHtml) {
		wrapExistingResults();

		var group = document.createElement("div");
		group.className = "result-group";
		group.setAttribute("data-group", resultGroupCounter);

		var now = new Date();
		var timeStr = now.toLocaleTimeString();

		var header = '<div class="result-group-header">';
		header += '<span class="group-timestamp">Run #' + resultGroupCounter + ' &mdash; ' + escapeHtml(timeStr) + '</span>';
		header += '<button class="btn-dismiss-group" data-group="' + resultGroupCounter + '" title="Dismiss this result">&times;</button>';
		header += '</div>';

		group.innerHTML = header + contentHtml;
		resultsContainer.insertBefore(group, resultsContainer.firstChild);

		// Bind dismiss button
		var dismissBtn = group.querySelector(".btn-dismiss-group");
		dismissBtn.addEventListener("click", function() {
			group.parentNode.removeChild(group);
			updateClearAllButton();
		});
	}

	function updateClearAllButton() {
		var hasGroups = resultsContainer.querySelectorAll(".result-group").length > 0;
		btnClearResults.classList.toggle("hidden", !hasGroups);
	}

	function hasHtmlTags(str) {
		return /<[a-zA-Z][^>]*>/.test(str);
	}

	// CFML may serialize booleans as strings ("true"/"false"/"YES"/"NO")
	function isTrue(val) {
		return val === true || val === "true" || val === "YES";
	}

	// Case-insensitive struct key lookup (CFML engines may uppercase keys)
	function getField(obj, field) {
		if (!obj || typeof obj !== "object") return undefined;
		if (obj[field] !== undefined) return obj[field];
		if (obj[field.toUpperCase()] !== undefined) return obj[field.toUpperCase()];
		if (obj[field.toLowerCase()] !== undefined) return obj[field.toLowerCase()];
		return undefined;
	}

	function bindResultEvents() {
		// Dismiss card buttons
		var dismissBtns = resultsContainer.querySelectorAll(".btn-dismiss-card");
		for (var d = 0; d < dismissBtns.length; d++) {
			if (dismissBtns[d].getAttribute("data-bound")) continue;
			dismissBtns[d].setAttribute("data-bound", "1");
			dismissBtns[d].addEventListener("click", function() {
				var card = this.closest(".result-card");
				if (card) {
					card.parentNode.removeChild(card);
					updateClearAllButton();
				}
			});
		}

		// Source toggle buttons
		var toggleBtns = resultsContainer.querySelectorAll(".btn-source-toggle");
		for (var i = 0; i < toggleBtns.length; i++) {
			// Skip buttons that already have a listener
			if (toggleBtns[i].getAttribute("data-bound")) continue;
			toggleBtns[i].setAttribute("data-bound", "1");
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

		// Refresh buttons
		var refreshBtns = resultsContainer.querySelectorAll(".btn-refresh");
		for (var r = 0; r < refreshBtns.length; r++) {
			if (refreshBtns[r].getAttribute("data-bound")) continue;
			refreshBtns[r].setAttribute("data-bound", "1");
			refreshBtns[r].addEventListener("click", function() {
				var idx = this.getAttribute("data-index");
				var btn = this;
				btn.classList.add("spinning");

				// Re-execute via the execute API (works for both iframe and static)
				var payloadFile = btn.getAttribute("data-payload");
				var engineKey = btn.getAttribute("data-engine");
				if (payloadFile && engineKey) {
					ajax("POST", "api2/execute.cfm", encodeParams({ payloadFile: payloadFile, engine: engineKey }), function(resp) {
						if (isTrue(resp.success) && resp.results && resp.results.length > 0) {
							var r = resp.results[0];
							var card = btn.closest(".result-card");
							if (card) {
								// Update header metadata
								var spans = card.querySelectorAll(".result-header span");
								// spans: engine-name, requestId, timestamp, duration
								if (spans.length >= 4) {
									spans[1].textContent = r.requestId;
									spans[2].textContent = r.timestamp;
									spans[3].textContent = r.duration + "ms";
								}

								// Update iframe src or body content
								var iframe = card.querySelector('.result-iframe[data-index="' + idx + '"]');
								if (iframe && r.interactiveURL) {
									iframe.setAttribute("data-src", r.interactiveURL);
									iframe.src = r.interactiveURL;
								} else {
									var body = card.querySelector('.result-body[data-index="' + idx + '"]');
									if (body) {
										body.innerHTML = isTrue(r.success) ? r.output : escapeHtml(r.error);
										body.setAttribute("data-html", body.innerHTML);
										body.classList.remove("source-view");
									}
									var toggle = card.querySelector('.btn-source-toggle[data-index="' + idx + '"]');
									if (toggle) toggle.textContent = "Source";
								}
							}
						}
						if (resp.payloadCount !== undefined) updatePayloadCount(resp.payloadCount);
						btn.classList.remove("spinning");
					});
				} else {
					btn.classList.remove("spinning");
				}
			});
		}

		// Store original HTML for source toggle (success + error-rendered, skip plain error-view)
		var bodies = resultsContainer.querySelectorAll(".result-body:not(.error-view):not([data-html])");
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
		tabBar.classList.add("hidden");
		if (currentDisplayMode === "side-by-side") {
			resultsContainer.classList.add("side-by-side");
		} else if (currentDisplayMode === "tabbed") {
			resultsContainer.classList.add("tabbed");
			tabBar.classList.remove("hidden");
			// Ensure the first card and tab are active
			var cards = resultsContainer.querySelectorAll(".result-card");
			var tabs = tabBar.querySelectorAll("button");
			if (cards.length > 0 && !resultsContainer.querySelector(".result-card.active")) {
				cards[0].classList.add("active");
				if (tabs.length > 0) tabs[0].classList.add("active");
			}
		}
	}

	// ===== Snippets =====
	function loadSnippetList() {
		ajax("GET", "api2/snippets.cfm", null, function(resp) {
			if (isTrue(resp.success) && resp.snippets) {
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
			if (isTrue(resp.success)) {
				editor.setValue(resp.content, -1);
				editor.gotoLine(1, 0, false);
			}
		});
	});

	// ===== Save Snippet =====
	btnSaveSnippet.addEventListener("click", function() {
		var code = editor.getValue();
		if (!code || !code.trim()) {
			swalFire({ icon: "warning", title: "Empty Editor", text: "Write some code before saving."});
			return;
		}
		swalFire({
			title: "Save Snippet",
			input: "text",
			inputLabel: "Filename (letters, numbers, hyphens, underscores)",
			inputPlaceholder: "my-snippet",
			inputValidator: function(value) {
				if (!value || !value.trim()) return "Filename is required.";
				if (/[^a-zA-Z0-9_\-]/.test(value.trim())) return "Only letters, numbers, hyphens, and underscores allowed.";
			},
			showCancelButton: true,
			confirmButtonText: "Save",
		}).then(function(result) {
			if (!result.isConfirmed) return;
			var filename = result.value.trim();
			ajax("POST", "api2/snippet-save.cfm", encodeParams({ filename: filename, code: code }), function(resp) {
				if (isTrue(resp.success)) {
					swalFire({
						toast: true, position: "top-end", icon: "success",
						title: "Saved as " + filename + ".cfm",
						showConfirmButton: false, timer: 2000
					});
					loadSnippetList();
				} else {
					swalFire({ icon: "error", title: "Save Failed", text: resp.error || "Unknown error"});
				}
			});
		});
	});

	// ===== Import GitHub Gist =====
	btnImportGist.addEventListener("click", function() {
		swalFire({
			title: "Import GitHub Gist",
			input: "url",
			inputLabel: "Paste a gist.github.com URL",
			inputPlaceholder: "https://gist.github.com/user/abc123",
			inputValidator: function(value) {
				if (!value || !value.trim()) return "URL is required.";
				if (!/^https?:\/\/gist\.github\.com\//i.test(value.trim())) return "URL must be from gist.github.com";
			},
			showCancelButton: true,
			confirmButtonText: "Import",
		}).then(function(result) {
			if (!result.isConfirmed) return;
			var gistUrl = result.value.trim();
			swalFire({
				title: "Importing...",
				allowOutsideClick: false,
				didOpen: function() { Swal.showLoading(); }
			});
			ajax("POST", "api2/gist-import.cfm", encodeParams({ url: gistUrl }), function(resp) {
				if (isTrue(resp.success)) {
					editor.setValue(resp.content, -1);
					editor.gotoLine(1, 0, false);
					swalFire({
						toast: true, position: "top-end", icon: "success",
						title: "Imported: " + (resp.filename || "gist"),
						showConfirmButton: false, timer: 2000
					});
				} else {
					swalFire({ icon: "error", title: "Import Failed", text: resp.error || "Unknown error"});
				}
			});
		});
	});

	// ===== Payload Count =====
	function updatePayloadCount(count) {
		if (count !== undefined && count !== null) {
			btnSession.textContent = count > 0 ? "Session (" + count + ")" : "Session";
		}
	}

	// ===== Clear All Results =====
	btnClearResults.addEventListener("click", function() {
		resultsContainer.innerHTML = "";
		updateClearAllButton();
	});

	// ===== Session Modal =====
	var sessionModal = document.getElementById("sessionModal");
	var btnCloseSession = document.getElementById("btnCloseSession");
	var btnArchiveAll = document.getElementById("btnArchiveAll");
	var sessionPayloads = document.getElementById("sessionPayloads");

	btnSession.addEventListener("click", function() {
		sessionModal.showModal();
		loadPayloadList();
	});
	btnCloseSession.addEventListener("click", function() {
		sessionModal.close();
	});
	sessionModal.addEventListener("click", function(e) {
		if (e.target === sessionModal) sessionModal.close();
	});

	function formatFileSize(bytes) {
		if (bytes < 1024) return bytes + " B";
		return (bytes / 1024).toFixed(1) + " KB";
	}

	function loadPayloadList() {
		sessionPayloads.innerHTML = '<div class="session-empty">Loading...</div>';
		ajax("GET", "api2/payloads.cfm", null, function(resp) {
			if (!isTrue(resp.success) || !resp.payloads || resp.payloads.length === 0) {
				sessionPayloads.innerHTML = '<div class="session-empty">No payload files in this session.</div>';
				btnArchiveAll.disabled = true;
				return;
			}
			btnArchiveAll.disabled = false;
			var html = '<ul class="payload-list">';
			for (var i = 0; i < resp.payloads.length; i++) {
				var p = resp.payloads[i];
				html += '<li class="payload-item" data-file="' + escapeHtml(p.name) + '" title="Click to load into editor">';
				html += '<span class="payload-time">' + escapeHtml(p.timestamp) + '</span>';
				html += '<span class="payload-name">' + escapeHtml(p.name) + '</span>';
				html += '<span class="payload-size">' + formatFileSize(p.size) + '</span>';
				html += '</li>';
			}
			html += '</ul>';
			sessionPayloads.innerHTML = html;

			// Bind click handlers
			var items = sessionPayloads.querySelectorAll(".payload-item");
			for (var j = 0; j < items.length; j++) {
				items[j].addEventListener("click", function() {
					var fileName = this.getAttribute("data-file");
					ajax("GET", "api2/payload-load.cfm?file=" + encodeURIComponent(fileName), null, function(resp) {
						if (isTrue(resp.success)) {
							editor.setValue(resp.content, -1);
							editor.gotoLine(1, 0, false);
							sessionModal.close();
							swalFire({
								toast: true, position: "top-end", icon: "success",
								title: "Loaded: " + (resp.file || "payload"),
								showConfirmButton: false, timer: 2000
							});
						} else {
							swalFire({ icon: "error", title: "Load Failed", text: resp.error || "Unknown error"});
						}
					});
				});
			}
		});
	}

	btnArchiveAll.addEventListener("click", function() {
		swalFire({
			title: "Archive All?",
			text: "Archive all payload files into a ZIP and start fresh?",
			icon: "question",
			showCancelButton: true,
			confirmButtonText: "Archive All"
		}).then(function(result) {
			if (!result.isConfirmed) return;
			ajax("GET", "api2/session-clear.cfm", null, function(resp) {
				if (isTrue(resp.success)) {
					updatePayloadCount(0);
					loadPayloadList();
					resultsContainer.innerHTML = '<div style="padding:16px;color:var(--accent-green);">Session archived.</div>';
				}
			});
		});
	});

	// ===== Reinit Application =====
	btnReinit.addEventListener("click", function() {
		btnReinit.disabled = true;
		btnReinit.textContent = "Reinitializing\u2026";
		ajax("GET", "api2/servers.cfm?reinit", null, function(resp) {
			btnReinit.disabled = false;
			btnReinit.textContent = "Reinit";
			if (isTrue(resp.success)) {
				pollServers();
				loadSnippetList();
				swalFire({
					toast: true,
					position: "top-end",
					icon: "success",
					title: "Application reinitialized",
					showConfirmButton: false,
					timer: 2000,
				});
			}
		});
	});

	// ===== Timeout Input =====
	timeoutInput.addEventListener("change", function() {
		var val = parseInt(this.value, 10) || 0;
		ajax("POST", "api2/config.cfm", encodeParams({ executionTimeout: val }), function() {});
	});

	// ===== Splitter (drag to resize editor/results) =====
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
	function formatUptime(isoTimestamp) {
		if (!isoTimestamp) return "";
		var start = new Date(isoTimestamp);
		var diff = Math.floor((Date.now() - start.getTime()) / 1000);
		if (isNaN(diff) || diff < 0) return "";
		var d = Math.floor(diff / 86400);
		var h = Math.floor((diff % 86400) / 3600);
		var m = Math.floor((diff % 3600) / 60);
		if (d > 0) return d + "d " + h + "h";
		if (h > 0) return h + "h " + m + "m";
		return m + "m";
	}

	function escapeHtml(str) {
		if (!str) return "";
		var div = document.createElement("div");
		div.appendChild(document.createTextNode(str));
		return div.innerHTML;
	}

	// ===== Initialize =====
	loadSnippetList();
	if (APP_CONFIG.useSSE) {
		startSSE();
	} else {
		startPolling();
	}

})();
