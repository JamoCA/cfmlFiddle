<!--- Ensure Application.cfc has loaded config into application scope --->
<cfparam name="application.config.editorTheme" default="monokai">
<cfparam name="application.config.clientPollInterval" default="10">
<cfparam name="application.config.startupTimeout" default="60">
<cfparam name="application.config.executionTimeout" default="0">
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CommandBox CFFiddle</title>
    <link rel="stylesheet" href="assets/css/style.css">
</head>
<body>

    <!--- ===== Top Bar ===== --->
    <div class="top-bar">
        <h1>CFFiddle</h1>

        <label for="snippetSelect">Snippet:</label>
        <select id="snippetSelect">
            <option value="">-- none --</option>
        </select>

        <label for="timeoutInput">Timeout (s):</label>
        <cfoutput>
        <input type="number" id="timeoutInput" value="#application.config.executionTimeout#" min="0" style="width:60px" title="Execution timeout in seconds (0 = disabled)">
        </cfoutput>

        <button id="btnClearSession" title="Archive temp files and start a new session">Clear Session</button>

        <div class="status-bar" id="statusBar" title="Click to manage servers">
            <!--- Populated by JavaScript --->
        </div>
    </div>

    <!--- ===== Editor Panel ===== --->
    <div class="editor-panel" id="editorPanel">
        <div id="editor"></div>
    </div>

    <!--- ===== Splitter ===== --->
    <div class="splitter" id="splitter"></div>

    <!--- ===== Controls Bar ===== --->
    <div class="controls-bar">
        <label for="engineSelect">Engine:</label>
        <select id="engineSelect">
            <option value="">-- select --</option>
        </select>
        <button class="btn-run btn-run-single" id="btnRun">Run</button>
        <button class="btn-run btn-run-all" id="btnRunAll">Run All Online</button>

        <div class="display-mode-toggle" id="displayModeToggle" style="margin-left:auto; display:none;">
            <button data-mode="stacked" class="active">Stacked</button>
            <button data-mode="side-by-side">Side by Side</button>
            <button data-mode="tabbed">Tabbed</button>
        </div>
    </div>

    <!--- ===== Tab Bar (for tabbed mode) ===== --->
    <div class="tab-bar" id="tabBar"></div>

    <!--- ===== Results Panel ===== --->
    <div class="results-panel">
        <div class="results-container" id="resultsContainer"></div>
    </div>

    <!--- ===== Admin Modal ===== --->
    <div class="modal-overlay" id="adminModal">
        <div class="modal">
            <button class="btn-modal-close" id="btnCloseModal">&times;</button>
            <h2>Server Management</h2>
            <div id="serverCards">
                <!--- Populated by JavaScript --->
            </div>
        </div>
    </div>

    <!--- ===== Ace Editor CDN ===== --->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ace.min.js" integrity="sha512-BHJlu9vUXVrcxhRwbBdNv3uTsbscp8pp3LJ5z/sw9nBJUegkNlkcZnvODRgynJWhXMCsVUGZlFuzTrr5I2X3sQ==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/theme-monokai.min.js" integrity="sha512-g9yptARGYXbHR9r3kTKIAzF+vvmgEieTxuuUUcHC5tKYFpLR3DR+lsisH2KZJG2Nwaou8jjYVRdbbbBQI3Bo5w==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ext-language_tools.min.js" integrity="sha512-pGeiKdzOOI7LQFQdSOoweS7JVXdwyKaigCy+04DZ34GzUI+9n0/vEg+pk1cVzN8owSr9c0X7dB/aCLNNvm3S5A==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-coldfusion.min.js" integrity="sha512-ZslkmZ4D+2Wp4LWOAhbRxIesLqGUK6TLOLAxwN6SXacAPnhulkda5MiachluWjqgC8fsbQahWWOe/VX+dsq4Cg==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/snippets/coldfusion.min.js" integrity="sha512-/q4t/H2FTC2kwXv+AMCZ+54UIdUFkjNxaSfhKRz982pbBAXHZzDRaH0k80QobC3Q4SNB6mi4/hc1s1btgoouNw==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-html.min.js" integrity="sha512-D64TbdwtINWYv5Qa8znJN5wDlSGYpzJGUXBJ82tt2Bmhq0V9qfH2u29AUMOKtzGlubvQnuGspZ0qKJX2XGLRaA==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>

    <!--- ===== App Config (passed from CFML to JS) ===== --->
    <cfoutput>
    <script>
        var APP_CONFIG = {
            clientPollInterval: #application.config.clientPollInterval# * 1000,
            startupTimeout: #application.config.startupTimeout#,
            editorTheme: "#encodeForJavaScript(application.config.editorTheme)#",
            executionTimeout: #application.config.executionTimeout#
        };
    </script>
    </cfoutput>

    <script src="assets/js/app.js"></script>
</body>
</html>
