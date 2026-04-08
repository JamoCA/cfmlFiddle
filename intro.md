# CommandBox CFFiddle

Build a web UI similar to the existing CFML online "fiddle" test suites:
- https://cffiddle.org/
- https://trycf.com/
- https://try.boxlang.io/

Use [Ace Editor](https://ace.c9.io/) via CDN at https://cdnjs.com/libraries/ace

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ace.min.js" integrity="sha512-BHJlu9vUXVrcxhRwbBdNv3uTsbscp8pp3LJ5z/sw9nBJUegkNlkcZnvODRgynJWhXMCsVUGZlFuzTrr5I2X3sQ==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/theme-monokai.min.js" integrity="sha512-g9yptARGYXbHR9r3kTKIAzF+vvmgEieTxuuUUcHC5tKYFpLR3DR+lsisH2KZJG2Nwaou8jjYVRdbbbBQI3Bo5w==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/ext-language_tools.min.js" integrity="sha512-pGeiKdzOOI7LQFQdSOoweS7JVXdwyKaigCy+04DZ34GzUI+9n0/vEg+pk1cVzN8owSr9c0X7dB/aCLNNvm3S5A==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-html.min.js" integrity="sha512-D64TbdwtINWYv5Qa8znJN5wDlSGYpzJGUXBJ82tt2Bmhq0V9qfH2u29AUMOKtzGlubvQnuGspZ0qKJX2XGLRaA==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/snippets/coldfusion.min.js" integrity="sha512-/q4t/H2FTC2kwXv+AMCZ+54UIdUFkjNxaSfhKRz982pbBAXHZzDRaH0k80QobC3Q4SNB6mi4/hc1s1btgoouNw==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.43.3/mode-coldfusion.min.js" integrity="sha512-ZslkmZ4D+2Wp4LWOAhbRxIesLqGUK6TLOLAxwN6SXacAPnhulkda5MiachluWjqgC8fsbQahWWOe/VX+dsq4Cg==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>

```

Any CFML server engine can currently be started using CommandBox (box.exe) and the `server.json` files located in the `./current-servers/` sub-directory.

CFML servers to support include: cf2016, cf2021, cf2023, cf2025, lucee5, lucee6, lucee7 & boxlang.

The JSON files start each server with a unique hostname & port. I guess there needs to be a default JSON template to identify basic configuration items... `app.libDirs`, `customTagPaths`, `jvm`, `aliases`, etc.  Please contrast and compare the files to determine what is unique versus platform-specific.

For example, for some CFML platforms, the `jvm.javaHome` may need to be designated to ensure that it's using the correct version of Java.

When starting up a new server, clone the template, deserialize the JSON (using `./JSONUtil/JSONUtil.cfc` to ensure consistency amongst platforms), add the specific server settings and launch with tray icon (in case it needs to be shut down manually.)  Use a unique server name in case a server with the same name has already been started and is running for another purpose.

Add elements to the web UI to determine if any of the servers are online/offline.  If not "online", offer the ability to "start" the server.  If online, offer the ability to "stop" the server.  This is preferable since not all servers need to always be online.  This should be a config page (or modal) that perform ajax posts and then polls the server status in the background.  Perhaps set up a heartbeat for online servers and display an indicator to visually dispaly that they are available.

When receiving a CFML payload and executing the script, retain the temp files during the "session". When starting a new session (or running a clean-up function in the UI), ZIP up past session files and archive them.  This is for later review in case anything caused a problem or needs to be investigated.

With all results, return a UUID of the request, ISO datestamp and the duration with the results.

Add a feature that will post the payload to be rendered by all online CFML servers and display the results in a stacked blocks.
