<!--- Ensure Application.cfc has loaded config into application scope --->
<cfparam name="application.config.editorTheme" default="monokai">
<cfparam name="application.config.clientPollInterval" default="10">
<cfparam name="application.config.startupTimeout" default="60">
<cfparam name="application.config.executionTimeout" default="0">
<cfparam name="application.config.useLocalAssets" default="true">
<cfparam name="application.config.useSSE" default="false">
<cfset useLocal = application.config.useLocalAssets>
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1.0">
	<script>
		(function() {
			var t = localStorage.getItem("cfmlfiddle-theme");
			if (!t) t = window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
			document.documentElement.setAttribute("data-theme", t);
		})();
	</script>
	<meta name="theme-color" content="#2d2d2d">
	<meta name="description" content="Self-hosted CFML playground - run code against multiple engines side by side">
	<title>CFMLFiddle</title>
	<link rel="stylesheet" href="assets/css/style.min.css">
	<cfoutput>
	<cfif useLocal>
		<link rel="stylesheet" href="assets/vendor/contextmenu/css/jquery.contextMenu.min.css">
	<cfelse>
		<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/jquery-contextmenu/2.9.2/jquery.contextMenu.min.css" crossorigin="anonymous" referrerpolicy="no-referrer">
	</cfif>
	</cfoutput>
	<link rel="icon" type="image/png" href="/assets/icon/favicon-96x96.png" sizes="96x96" />
	<link rel="icon" type="image/svg+xml" href="/assets/icon/favicon.svg" />
	<link rel="shortcut icon" href="/assets/icon/favicon.ico" />
	<link rel="apple-touch-icon" sizes="180x180" href="/assets/icon/apple-touch-icon.png" />
	<link rel="manifest" href="/assets/icon/site.webmanifest" />
</head>
<body>
	<a href="#editor" class="skip-link">Skip to editor</a>

	<!--- ===== Top Bar ===== --->
	<div class="top-bar" role="toolbar" aria-label="Main toolbar">
		<h1><img src="assets/icon/favicon-96x96.png" alt="" class="logo">CFMLFiddle</h1>

		<label for="snippetSelect">Snippet:</label>
		<select id="snippetSelect">
			<option value="">-- none --</option>
		</select>
		<button id="btnSaveSnippet" title="Save current code as a snippet">Save</button>
		<button id="btnImportGist" title="Import a GitHub Gist">Gist</button>

		<label for="timeoutInput">Timeout (s):</label>
		<cfoutput>
		<input type="number" id="timeoutInput" value="#application.config.executionTimeout#" min="0" class="timeout-input" title="Execution timeout in seconds (0 = disabled)">
		</cfoutput>

		<button id="btnSession" title="View session payloads">Session</button>
		<button id="btnReinit" title="Reinitialize the application (reload config, re-scan servers)">Reinit</button>

		<div class="status-bar" id="statusBar" role="button" tabindex="0" title="Click to manage servers" aria-label="Server status - click to manage">
			<!--- Populated by JavaScript --->
		</div>

		<button class="btn-theme" id="btnTheme" title="Toggle light/dark theme" aria-label="Toggle light/dark theme">&#x263E;</button>
		<button class="btn-about" id="btnAbout" title="About CFMLFiddle" aria-label="About CFMLFiddle">?</button>
	</div>

	<!--- ===== Editor Panel ===== --->
	<div class="editor-panel" id="editorPanel">
		<div id="editor"></div>
	</div>

	<!--- ===== Splitter ===== --->
	<div class="splitter" id="splitter" role="separator" aria-orientation="horizontal" aria-label="Resize editor and results panels" tabindex="0"></div>

	<!--- ===== Controls Bar ===== --->
	<div class="controls-bar" role="toolbar" aria-label="Execution controls">
		<label for="engineSelect">Engine:</label>
		<select id="engineSelect">
			<option value="">-- select --</option>
		</select>
		<button class="btn-run btn-run-single" id="btnRun">Run</button>
		<button class="btn-run btn-run-all" id="btnRunAll">Run All Online</button>

		<label class="append-toggle" title="Keep previous results and stack new ones below">
			<input type="checkbox" id="chkAppend"> Append
		</label>
		<label class="append-toggle" title="Force all results into interactive iframe mode (auto-detects forms when unchecked)">
			<input type="checkbox" id="chkInteractive"> Interactive
		</label>
		<button class="btn-clear-results hidden" id="btnClearResults" title="Dismiss all results">Clear All</button>

		<div class="display-mode-toggle hidden" id="displayModeToggle">
			<button data-mode="stacked" class="active">Stacked</button>
			<button data-mode="side-by-side">Side by Side</button>
			<button data-mode="tabbed">Tabbed</button>
		</div>
	</div>

	<!--- ===== Tab Bar (for tabbed mode) ===== --->
	<div class="tab-bar" id="tabBar"></div>

	<!--- ===== Results Panel ===== --->
	<div class="results-panel" id="resultsPanel">
		<div class="results-container" id="resultsContainer" aria-live="polite" aria-label="Execution results"></div>
	</div>

	<!--- ===== Session Modal ===== --->
	<dialog class="modal modal-session" id="sessionModal" aria-labelledby="sessionModalTitle">
		<button class="btn-modal-close" id="btnCloseSession" aria-label="Close">&times;</button>
		<h2 id="sessionModalTitle">Session Payloads</h2>
		<div class="session-actions">
			<button class="btn-archive-all" id="btnArchiveAll" title="Archive all payloads and start fresh">Archive All</button>
		</div>
		<div id="sessionPayloads">
			<!--- Populated by JavaScript --->
		</div>
	</dialog>

	<!--- ===== Admin Modal ===== --->
	<dialog class="modal" id="adminModal" aria-labelledby="adminModalTitle">
		<button class="btn-modal-close" id="btnCloseModal" aria-label="Close">&times;</button>
		<h2 id="adminModalTitle">Server Management</h2>
		<label class="modal-option" title="Show the CommandBox console window during server startup for troubleshooting">
			<input type="checkbox" id="chkShowConsole"> Show console on startup
		</label>
		<div id="serverCards">
			<!--- Populated by JavaScript --->
		</div>
	</dialog>

	<!--- ===== About Modal ===== --->
	<dialog class="modal modal-about" id="aboutModal" aria-labelledby="aboutModalTitle">
		<button class="btn-modal-close" id="btnCloseAbout" aria-label="Close">&times;</button>
			<cfoutput><h2 id="aboutModalTitle"><img src="assets/icon/favicon-96x96.png" alt="" class="about-logo">CFMLFiddle <span class="about-version">v#application.config.version#</span></h2></cfoutput>

			<div class="about-content">
				<h3>About</h3>
				<p>
					CFMLFiddle is an open-source, self-hosted CFML playground powered by
					<a href="https://www.ortussolutions.com/products/commandbox" target="_blank" rel="nofollow noopener noreferrer">CommandBox</a>.
				</p>
				<p>
					There are several online CFML tools worth knowing about:
					<a href="https://cffiddle.org" target="_blank" rel="nofollow noopener noreferrer">CFFiddle.org</a>,
					<a href="https://trycf.com" target="_blank" rel="nofollow noopener noreferrer">TryCF.com</a>, and
					<a href="https://try.boxlang.io/" target="_blank" rel="nofollow noopener noreferrer">Try BoxLang</a>
					all let you run CFML in a browser. They're useful when you need
					a quick test and don't have a local environment handy.
				</p>
				<p>
					CFMLFiddle does something different. It runs on your machine,
					so you pick the exact engine versions you want, compare results
					across all of them at once, and don't need to log into anything.
					If you've ever needed to check whether a behavior changed between
					CF2021 and CF2025, or see how Lucee handles something differently,
					that's what this is for.
				</p>

				<h3>Quick Start</h3>
				<ol>
					<li>Select an engine from the <strong>Engine</strong> dropdown (or click the status bar to start one).</li>
					<li>Write your CFML code in the editor.</li>
					<li>Click <strong>Run</strong> to execute against the selected engine, or <strong>Run All Online</strong> to execute on every running engine simultaneously.</li>
					<li>Toggle <strong>Append</strong> to stack results from multiple runs.</li>
					<li>Use <strong>Source/Rendered</strong> to toggle between HTML output and raw source.</li>
					<li><strong>Clear Session</strong> archives all temporary payload files
						into a dated ZIP file and removes them from the working directory.
						Identical code reuses the same file, so the count only grows when
						you change your code.</li>
				</ol>

				<h3>Supported Engines</h3>
				<table class="about-table">
					<thead>
						<tr><th>Engine</th><th>Website</th></tr>
					</thead>
					<tbody>
						<tr>
							<td>Adobe ColdFusion</td>
							<td><a href="https://coldfusion.adobe.com/" target="_blank" rel="nofollow noopener noreferrer">coldfusion.adobe.com</a></td>
						</tr>
						<tr>
							<td>Lucee CFML</td>
							<td><a href="https://www.lucee.org/" target="_blank" rel="nofollow noopener noreferrer">lucee.org</a></td>
						</tr>
						<tr>
							<td>BoxLang</td>
							<td><a href="https://boxlang.io/" target="_blank" rel="nofollow noopener noreferrer">boxlang.io</a></td>
						</tr>
						<tr>
							<td>CommandBox</td>
							<td><a href="https://www.ortussolutions.com/products/commandbox" target="_blank" rel="nofollow noopener noreferrer">ortussolutions.com</a></td>
						</tr>
					</tbody>
				</table>

				<h3>Libraries</h3>
				<table class="about-table">
					<thead>
						<tr><th>Library</th><th>License</th><th>Website</th></tr>
					</thead>
					<tbody>
						<tr>
							<td>Ace Editor</td>
							<td>BSD 3-Clause</td>
							<td><a href="https://ace.c9.io/" target="_blank" rel="nofollow noopener noreferrer">ace.c9.io</a></td>
						</tr>
						<tr>
							<td>SweetAlert2</td>
							<td>MIT</td>
							<td><a href="https://sweetalert2.github.io/" target="_blank" rel="nofollow noopener noreferrer">sweetalert2.github.io</a></td>
						</tr>
						<tr>
							<td>jQuery</td>
							<td>MIT</td>
							<td><a href="https://jquery.com/" target="_blank" rel="nofollow noopener noreferrer">jquery.com</a></td>
						</tr>
						<tr>
							<td>jQuery contextMenu</td>
							<td>MIT</td>
							<td><a href="https://swisnl.github.io/jQuery-contextMenu/" target="_blank" rel="nofollow noopener noreferrer">swisnl.github.io/jQuery-contextMenu</a></td>
						</tr>
						<tr>
							<td>JSONUtil</td>
							<td>Apache 2.0</td>
							<td><a href="https://github.com/CFCommunity/jsonutil" target="_blank" rel="nofollow noopener noreferrer">github.com/CFCommunity/jsonutil</a></td>
						</tr>
						<tr>
							<td>cf_dump</td>
							<td>MIT</td>
							<td><a href="https://github.com/kwaschny/cf_dump" target="_blank" rel="nofollow noopener noreferrer">github.com/kwaschny/cf_dump</a></td>
						</tr>
					</tbody>
				</table>

				<h3>Credits</h3>
				<p>
					Created by <a href="https://www.mycfml.com/" target="_blank" rel="nofollow noopener noreferrer">myCFML.com</a><br>
					Sponsored by <a href="https://www.sunstarmedia.com/" target="_blank" rel="nofollow noopener noreferrer">SunStar Media</a>
				</p>

				<h3>License</h3>
				<p>
					CFMLFiddle is released under the
					<a href="https://opensource.org/licenses/MIT" target="_blank" rel="nofollow noopener noreferrer">MIT License</a>.
					You are free to use, modify, and distribute this software.
				</p>
			</div>
	</dialog>

	<!--- ===== Vendor Libraries (local or CDN) ===== --->
	<cfoutput>
	<cfif useLocal>
		<script src="assets/vendor/jquery/jquery.min.js"></script>
		<script src="assets/vendor/sweetalert2/sweetalert2.all.min.js"></script>
		<script src="assets/vendor/contextmenu/js/jquery.ui.position.min.js"></script>
		<script src="assets/vendor/contextmenu/js/jquery.contextMenu.min.js"></script>
		<script src="assets/vendor/ace/ace.min.js"></script>
		<script src="assets/vendor/ace/theme-monokai.min.js"></script>
		<script src="assets/vendor/ace/theme-chrome.min.js"></script>
		<script src="assets/vendor/ace/ext-language_tools.min.js"></script>
		<script src="assets/vendor/ace/mode-coldfusion.min.js"></script>
		<script src="assets/vendor/ace/snippets/coldfusion.min.js"></script>
		<script src="assets/vendor/ace/mode-html.min.js"></script>
	<cfelse>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery-contextmenu/2.9.2/jquery.ui.position.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery-contextmenu/2.9.2/jquery.contextMenu.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ace.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/theme-monokai.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/theme-chrome.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ext-language_tools.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-coldfusion.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/snippets/coldfusion.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
		<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-html.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
	</cfif>
	</cfoutput>

	<!--- ===== App Config (passed from CFML to JS) ===== --->
	<cfoutput>
	<script>
		var APP_CONFIG = {
			"clientPollInterval": #application.config.clientPollInterval# * 1000,
			"startupTimeout": #application.config.startupTimeout#,
			"editorTheme": "#encodeForJavaScript(application.config.editorTheme)#",
			"executionTimeout": #application.config.executionTimeout#,
			"useSSE": #application.config.useSSE ? "true" : "false"#
		};
	</script>
	</cfoutput>

	<script src="assets/js/app.min.js"></script>
</body>
</html>
