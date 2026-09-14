import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "marcuspelo.omarqui"
  ipcTarget: "marcuspelo.omarqui"

  readonly property string baseUrl: {
    var v = settings ? settings.baseUrl : undefined
    if (typeof v === "string" && v.length > 0) return v
    if (root.envBaseUrl) return root.envBaseUrl
    return "http://localhost:7476"
  }
  readonly property int pollInterval: {
    var v = settings ? settings.refreshIntervalSec : undefined
    return (typeof v === "number" && v >= 5) ? v : 10
  }
  readonly property string barMetric: {
    var v = settings ? settings.barMetric : undefined
    return (v === "Upload" || v === "Both") ? v : "Download"
  }
  readonly property string barStyle: {
    var v = settings ? settings.barStyle : undefined
    return v === "Logo" ? v : "Speed"
  }
  // How the logo reacts while any torrent is transferring (see QuiLogo).
  readonly property var activityKeys: ["Static", "Pulse", "Dim", "Tint", "Underline", "Corners", "BesideUpDown", "BesideDownUp", "Drift"]
  readonly property string logoActivity: {
    var v = settings ? settings.logoActivity : undefined
    return root.activityKeys.indexOf(v) !== -1 ? v : "Pulse"
  }
  // Direction marks paint in the bar colour or in the widget's own
  // downloading / seeding colours (the ones the torrent list uses).
  readonly property string arrowColor: {
    var v = settings ? settings.arrowColor : undefined
    return v === "State" ? v : "Bar"
  }
  // Colour the mark takes in Tint mode: "accent", "urgent" or a #rrggbb.
  readonly property string tintColor: root.normalizeTint(settings ? settings.tintColor : undefined)
  readonly property bool showLogo: root.barStyle === "Logo"
  readonly property bool settingsShown: root.opened && root.viewMode === "settings"
  // The activity tiles only animate while they are actually on screen.
  readonly property bool logoTilesLive: root.settingsShown && root.settingsTab === "bar" && root.showLogo
  // One cap for the popup card. The settings Flickable derives its own from
  // it (see settingsFlick) so the card and its scroller cannot disagree.
  readonly property real panelMaxHeight: Style.space(root.viewMode === "settings" ? 720 : 620)
  // The arrow column in the Beside layouts sits past the icon canvas.
  readonly property real logoExtraWidth: (root.logoActivity === "BesideUpDown" || root.logoActivity === "BesideDownUp")
    ? 9 * Style.bar.iconCanvas / 16 : 0

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"
  readonly property string barIcon: "󰇚"
  readonly property color urgentColor: root.bar ? root.bar.urgent : Color.urgent
  // Download / upload colours, with darker variants for a light surface
  // (light theme, or a transparent bar over a bright wallpaper) where the
  // pastel pair all but disappears.
  readonly property color downColor: "#7aa2f7"
  readonly property color upColor: "#8fd694"
  readonly property color downColorOnLight: "#2b5fc7"
  readonly property color upColorOnLight: "#15703a"
  function onLightSurface(fg) {
    var c = Qt.color(fg)
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
  }
  function downColorFor(fg) { return root.onLightSurface(fg) ? root.downColorOnLight : root.downColor }
  function upColorFor(fg) { return root.onLightSurface(fg) ? root.upColorOnLight : root.upColor }

  // Everything the logo is painted with, in one place: the bar instance and
  // the settings previews read the same values, so a tile shows exactly what
  // the bar draws. `barForeground` (not `fg`) is what the bar icon uses — it
  // flips to the auto-picked legible colour when the bar goes transparent.
  readonly property color logoMarkColor: root.hasError ? root.urgentColor : root.barForeground
  // No halo over a transparent bar: a solid disc would sit on the wallpaper.
  readonly property color logoHaloColor: (root.bar && !root.bar.transparent) ? root.bar.background : "transparent"
  readonly property color logoDownColor: root.downColorFor(root.barForeground)
  readonly property color logoUpColor: root.upColorFor(root.barForeground)
  // Vertical space the bar gives the icon, so the underline can be kept
  // inside a short bar. 0 on a vertical bar, where height is unconstrained.
  readonly property real logoBarHeight: (root.bar && !root.bar.vertical) ? root.bar.barSize : 0

  // Per-direction activity across every instance drives the logo marks.
  // An errored widget shows the plain mark, so the error state is folded in
  // here rather than repeated at every consumer.
  readonly property bool downloading: !root.hasError && (Number(root.stats.totalDownloadSpeed) || 0) > 0
  readonly property bool uploading: !root.hasError && (Number(root.stats.totalUploadSpeed) || 0) > 0

  property string apiKey: ""
  property string envBaseUrl: ""
  property bool apiKeyLoaded: false
  property var stats: ({})
  property var instances: []
  property bool loading: false
  property bool hasError: false
  property string errorText: ""

  property var rawTorrents: []
  property bool torrentsLoading: false
  property string searchQuery: ""
  property int selectedInstanceId: -1
  property string statusFilter: ""
  property string actionInProgress: ""
  property string confirmDeleteHash: ""

  property var torrents: {
    var list = root.rawTorrents
    if (root.selectedInstanceId !== -1)
      list = list.filter(function(t) { return t.instance_id === root.selectedInstanceId })
    if (root.statusFilter)
      list = list.filter(function(t) { return root.matchesStatusFilter(t, root.statusFilter) })
    return list
  }

  // Not provided by Qui's cross-instance stats endpoint, so derived client-side
  // from the same rawTorrents list the other StatChip counts are sourced from.
  property int activeCount: {
    var list = root.rawTorrents
    var n = 0
    for (var i = 0; i < list.length; i++) {
      if ((Number(list[i].dlspeed) || 0) > 0 || (Number(list[i].upspeed) || 0) > 0) n++
    }
    return n
  }

  property string viewMode: "list"
  property var categories: []
  property int addInstanceId: -1
  property string addCategory: ""
  property string addSource: ""
  property bool addPaused: false
  property bool addSubmitting: false
  property string addStatusText: ""
  property bool addStatusError: false

  // Settings apply as they change (the omarchy convention: clock, power and
  // the bar toggles all persist on click). Text fields commit on Enter or
  // focus loss. `settingsTab` remembers the open tab for the session.
  property string settingsTab: "connection"
  property string settingsStatusText: ""
  property string hexStatusText: ""
  // Working value for the custom tint chip, kept even while a preset is
  // selected so switching back does not lose what was typed.
  property string customTint: "#c678dd"
  property bool tintCustomSelected: false
  // The hex field lives inside the lazily loaded Bar tab, so its focus state
  // is mirrored here for the panel's key catcher.
  property bool tintFieldFocused: false

  readonly property var tintPresets: [
    { key: "accent", label: "Theme accent" },
    { key: "#7aa2f7", label: "Blue" },
    { key: "#8fd694", label: "Green" },
    { key: "urgent", label: "Theme urgent" },
    { key: "custom", label: "Custom" }
  ]

  function isDirectionActivity(a) {
    return a === "Underline" || a === "Corners" || a === "BesideUpDown" || a === "BesideDownUp" || a === "Drift"
  }

  // Colour validation and resolution both go through the kit's resolver, so
  // the widget accepts exactly what the rest of the shell accepts: the theme
  // tokens below, or a hex colour (#rgb, #rrggbb, #rrggbbaa).
  readonly property var tintTokens: ["accent", "urgent", "foreground", "text", "background", "transparent"]

  function isHexColor(v) {
    return Style.colorFromHex(v, null) !== null
  }

  function normalizeTint(v) {
    v = String(v || "").trim().toLowerCase()
    if (root.tintTokens.indexOf(v) !== -1) return v
    return root.isHexColor(v) ? v : "accent"
  }

  function resolveTint(v) {
    return Style.resolveStateColor(v, root.fg, Color.accent, root.urgentColor, Color.accent)
  }

  function isTintPreset(v) {
    for (var i = 0; i < root.tintPresets.length; i++) {
      if (root.tintPresets[i].key !== "custom" && root.tintPresets[i].key === v) return true
    }
    return false
  }

  readonly property string tintChoice: (root.tintCustomSelected || !root.isTintPreset(root.tintColor)) ? "custom" : root.tintColor

  // Keep the working value in step with a tint set from outside the panel
  // (omarchy bar set, another screen's instance), so the field shows it and
  // the next focus-out does not write the stale one back. A half-typed value
  // is safe: tintColor only changes once something commits.
  onTintColorChanged: if (!root.isTintPreset(root.tintColor)) root.customTint = root.tintColor

  function activityLabel(a) {
    switch (a) {
      case "Static": return "Static"
      case "Pulse": return "Pulse"
      case "Dim": return "Dim idle"
      case "Tint": return "Tint"
      case "Underline": return "Underline"
      case "Corners": return "Corners"
      case "BesideUpDown": return "Beside ↑↓"
      case "BesideDownUp": return "Beside ↓↑"
      case "Drift": return "Drift"
    }
    return a
  }

  function activityDescription(a) {
    switch (a) {
      case "Static": return "Nothing changes. Speeds live in the tooltip only."
      case "Pulse": return "Whole mark fades to 45 % and back every 1.6 s."
      case "Dim": return "Idle mark at 42 %, full when transferring."
      case "Tint": return "Mark changes colour while transferring. Defaults to the theme accent (note: several themes set accent = text, so pick one)."
      case "Underline": return "2 px line under the mark: left half = download, right half = upload."
      case "Corners": return "↓ bottom-left, ↑ bottom-right, each only while its direction is active."
      case "BesideUpDown": return "↑ above, ↓ below, in a column next to the mark. Dim when off, lit when on."
      case "BesideDownUp": return "Same column, download first: ↓ above, ↑ below."
      case "Drift": return "One corner arrow slides 3 px in its direction over 2.8 s and fades. In Both, ↓ and ↑ take turns."
    }
    return ""
  }

  // Sent over each curl process's stdin via -K - (see the Process blocks
  // below) instead of a -H argument, so the API key never appears in argv.
  function apiKeyHeaderConfig() {
    return 'header = "X-API-Key: ' + root.apiKey + '"\n'
  }

  function formatSpeed(bytesPerSec) {
    var v = Number(bytesPerSec) || 0
    if (v < 1024) return v.toFixed(0) + " B/s"
    if (v < 1024 * 1024) return (v / 1024).toFixed(0) + " K/s"
    return (v / 1024 / 1024).toFixed(1) + " M/s"
  }

  function barText() {
    if (root.barMetric === "Upload")
      return "↑ " + root.formatSpeed(root.stats.totalUploadSpeed)
    if (root.barMetric === "Both")
      return "↓ " + root.formatSpeed(root.stats.totalDownloadSpeed)
        + "  ↑ " + root.formatSpeed(root.stats.totalUploadSpeed)
    return "↓ " + root.formatSpeed(root.stats.totalDownloadSpeed)
  }

  function formatBytes(bytes) {
    var v = Number(bytes) || 0
    if (v < 1024) return v.toFixed(0) + " B"
    if (v < 1024 * 1024) return (v / 1024).toFixed(0) + " KB"
    if (v < 1024 * 1024 * 1024) return (v / 1024 / 1024).toFixed(1) + " MB"
    return (v / 1024 / 1024 / 1024).toFixed(1) + " GB"
  }

  function stateLabel(state) {
    var s = String(state || "")
    if (s.indexOf("error") !== -1 || s === "missingFiles" || s === "unknown") return "error"
    if (s.indexOf("checking") !== -1) return "checking"
    if (s.indexOf("paused") === 0 || s.indexOf("stopped") === 0) return "paused"
    if (s === "downloading" || s.indexOf("DL") !== -1 || s === "allocating" || s === "metaDL") return "downloading"
    if (s === "uploading" || s.indexOf("UP") !== -1) return "seeding"
    return s || "—"
  }

  function stateColor(state) {
    var s = String(state || "")
    if (s.indexOf("error") !== -1 || s === "missingFiles" || s === "unknown") return Color.urgent
    if (s.indexOf("paused") === 0 || s.indexOf("stopped") === 0) return root.dim
    if (s === "downloading" || s.indexOf("DL") !== -1 || s === "allocating" || s === "metaDL") return root.downColorFor(root.fg)
    if (s === "uploading" || s.indexOf("UP") !== -1) return root.upColorFor(root.fg)
    return root.dim
  }

  function isPaused(state) {
    var s = String(state || "")
    return s.indexOf("paused") === 0 || s.indexOf("stopped") === 0
  }

  function matchesStatusFilter(torrent, filter) {
    var s = String(torrent.state || "")
    if (filter === "downloading") return s === "downloading" || s.indexOf("DL") !== -1 || s === "allocating" || s === "metaDL"
    if (filter === "seeding") return s === "uploading" || s.indexOf("UP") !== -1
    if (filter === "paused") return s.indexOf("paused") === 0 || s.indexOf("stopped") === 0
    if (filter === "error") return s.indexOf("error") !== -1 || s === "missingFiles" || s === "unknown"
    if (filter === "active") return (Number(torrent.dlspeed) || 0) > 0 || (Number(torrent.upspeed) || 0) > 0
    return true
  }

  function toggleStatusFilter(key) {
    root.statusFilter = root.statusFilter === key ? "" : key
  }

  function parseEnv(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line || line.indexOf("#") === 0) continue
      var eq = line.indexOf("=")
      if (eq < 0) continue
      var key = line.substring(0, eq).trim()
      var value = line.substring(eq + 1).trim().replace(/^["']|["']$/g, "")
      if (key === "API_KEY") root.apiKey = value
      else if (key === "BASE_URL") root.envBaseUrl = value
    }
    apiKeyLoaded = true
  }

  function refresh() {
    if (!apiKeyLoaded) return
    if (!apiKey) {
      hasError = true
      errorText = "API key not configured in .env"
      return
    }
    if (!statsProc.running) {
      loading = true
      statsProc.command = ["curl", "-fsS", "--max-time", "6", "-K", "-",
        root.baseUrl + "/api/torrents/cross-instance?limit=1"]
      statsProc.stdinEnabled = true
      statsProc.running = true
    }
    if (!instancesProc.running) {
      instancesProc.command = ["curl", "-fsS", "--max-time", "6", "-K", "-",
        root.baseUrl + "/api/instances"]
      instancesProc.stdinEnabled = true
      instancesProc.running = true
    }
  }

  function handleStats(raw) {
    loading = false
    try {
      var data = JSON.parse(String(raw || ""))
      stats = data.stats || {}
      hasError = false
      errorText = ""
    } catch (e) {
      hasError = true
      errorText = "Failed to read Qui response"
    }
  }

  function handleInstances(raw) {
    try {
      instances = JSON.parse(String(raw || "")) || []
    } catch (e) {
      instances = []
    }
  }

  function fetchTorrents() {
    if (!apiKey || torrentsProc.running) return
    torrentsLoading = true
    var url = root.baseUrl + "/api/torrents/cross-instance?limit=500&sort=added_on&order=desc"
    if (searchQuery) url += "&search=" + encodeURIComponent(searchQuery)
    torrentsProc.command = ["curl", "-fsS", "--max-time", "8", "-K", "-", url]
    torrentsProc.stdinEnabled = true
    torrentsProc.running = true
  }

  function handleTorrents(raw) {
    torrentsLoading = false
    try {
      var data = JSON.parse(String(raw || ""))
      rawTorrents = data.cross_instance_torrents || []
    } catch (e) {
      rawTorrents = []
    }
  }

  function selectInstance(id) {
    root.selectedInstanceId = id
    root.fetchTorrents()
  }

  function torrentAction(torrent, action) {
    if (!torrent || actionProc.running) return
    root.actionInProgress = torrent.hash + ":" + action
    actionProc.command = ["curl", "-fsS", "--max-time", "8", "-X", "POST", "-K", "-",
      "-H", "Content-Type: application/json",
      "-d", JSON.stringify({ action: action, hashes: [torrent.hash] }),
      root.baseUrl + "/api/instances/" + torrent.instance_id + "/torrents/bulk-action"]
    actionProc.stdinEnabled = true
    actionProc.running = true
  }

  function triggerPress(button) {
    if (button === Qt.MiddleButton) { refresh(); return }
    if (opened) close(); else { open(); refresh() }
  }

  function openAddView() {
    root.viewMode = "add"
    root.addStatusText = ""
    root.addStatusError = false
    if (root.addInstanceId === -1 && root.instances.length > 0)
      root.addInstanceId = root.instances[0].id
    if (root.addInstanceId !== -1) root.fetchCategories(root.addInstanceId)
  }

  function closeAddView() {
    root.viewMode = "list"
  }

  // The two text fields bind to `root.baseUrl` / `root.customTint` rather than
  // being seeded here, so a change made elsewhere (omarchy bar set, another
  // screen's instance) shows up instead of being reverted on the next commit.
  function openSettingsView() {
    root.viewMode = "settings"
    if (!root.isTintPreset(root.tintColor)) root.customTint = root.tintColor
    root.tintCustomSelected = !root.isTintPreset(root.tintColor)
    root.settingsStatusText = ""
    root.hexStatusText = ""
  }

  function closeSettingsView() {
    root.viewMode = "list"
  }

  function canPersistSettings() {
    return !!(root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
  }

  // Merge `values` into the widget settings and write them through to the
  // bar layout, so the change is live and survives a restart.
  function persistSettings(values) {
    var entry = {}
    for (var existing in root.settings) entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.canPersistSettings()) {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
      root.settingsStatusText = ""
    } else {
      root.settingsStatusText = "Changes apply for this session only (bar unavailable)"
    }
  }

  // Only writes when the effective URL actually changes, so opening and
  // leaving the field does not bake the .env / default fallback into
  // shell.json (which would then survive a later .env edit).
  function commitBaseUrl(text) {
    var url = String(text || "").trim()
    if (!url) url = root.envBaseUrl || "http://localhost:7476"
    if (url === root.baseUrl) return
    root.persistSettings({ baseUrl: url })
    root.hasError = false
    root.errorText = ""
    root.refresh()
    root.fetchTorrents()
  }

  function setRefreshInterval(v) {
    var interval = Math.max(5, Math.min(300, Math.round(Number(v) || 10)))
    if (interval !== root.pollInterval) root.persistSettings({ refreshIntervalSec: interval })
  }

  function selectTint(key) {
    if (key === "custom") {
      root.tintCustomSelected = true
      root.commitCustomTint()
      return
    }
    root.tintCustomSelected = false
    root.hexStatusText = ""
    root.persistSettings({ tintColor: key })
  }

  // Reads the working value rather than the field, so the Bar tab can live
  // behind a Loader (the field's id is not visible from out here).
  function commitCustomTint() {
    var v = String(root.customTint || "").trim().toLowerCase()
    root.customTint = v
    if (!root.isHexColor(v)) {
      root.hexStatusText = "Enter a hex colour: #rgb, #rrggbb or #rrggbbaa"
      return
    }
    root.hexStatusText = ""
    if (v !== root.tintColor) root.persistSettings({ tintColor: v })
  }

  function selectAddInstance(id) {
    root.addInstanceId = id
    root.addCategory = ""
    root.fetchCategories(id)
  }

  function fetchCategories(instanceId) {
    if (!apiKey || categoriesProc.running) return
    categoriesProc.command = ["curl", "-fsS", "--max-time", "6", "-K", "-",
      root.baseUrl + "/api/instances/" + instanceId + "/categories"]
    categoriesProc.stdinEnabled = true
    categoriesProc.running = true
  }

  function handleCategories(raw) {
    try {
      var data = JSON.parse(String(raw || "")) || {}
      categories = Object.keys(data).sort()
    } catch (e) {
      categories = []
    }
  }

  function submitAddTorrent() {
    if (addTorrentProc.running) return
    var src = String(root.addSource || "").trim()
    if (!src) {
      root.addStatusError = true
      root.addStatusText = "Paste a magnet link or provide the path to a .torrent file"
      return
    }
    if (root.addInstanceId === -1) {
      root.addStatusError = true
      root.addStatusText = "Choose an instance"
      return
    }
    root.addSubmitting = true
    root.addStatusError = false
    root.addStatusText = ""

    var args = ["curl", "-s", "--max-time", "20", "-X", "POST", "-K", "-",
      "-F", "paused=" + (root.addPaused ? "true" : "false")]
    if (root.addCategory) args = args.concat(["-F", "category=" + root.addCategory])

    var isRemote = src.indexOf("magnet:") === 0 || src.indexOf("http://") === 0 || src.indexOf("https://") === 0
    if (isRemote) {
      args = args.concat(["-F", "urls=" + src])
    } else {
      var path = src.indexOf("~/") === 0 ? (Quickshell.env("HOME") + src.substring(1)) : src
      args = args.concat(["-F", "torrent=@" + path + ";type=application/x-bittorrent"])
    }
    args = args.concat(["-w", "\n---HTTP:%{http_code}",
      root.baseUrl + "/api/instances/" + root.addInstanceId + "/torrents"])

    addTorrentProc.command = args
    addTorrentProc.stdinEnabled = true
    addTorrentProc.running = true
  }

  function handleAddTorrentResult(raw) {
    root.addSubmitting = false
    var text = String(raw || "")
    var marker = text.lastIndexOf("\n---HTTP:")
    var status = 0
    var body = text
    if (marker !== -1) {
      status = parseInt(text.substring(marker + 9)) || 0
      body = text.substring(0, marker)
    }
    if (status >= 200 && status < 300) {
      root.addStatusError = false
      root.addStatusText = "Torrent added!"
      root.addSource = ""
      root.refresh()
      root.fetchTorrents()
      addSuccessTimer.restart()
    } else {
      root.addStatusError = true
      var msg = body.trim()
      try {
        var parsed = JSON.parse(body)
        msg = parsed.error || parsed.message || msg
      } catch (e) {}
      root.addStatusText = msg || ("Failed to add torrent (HTTP " + status + ")")
    }
  }

  component StatChip: Text {
    id: chip
    property string filterKey: ""
    property string label: ""
    property int count: 0

    text: count + " " + label
    color: root.statusFilter === filterKey ? Color.accent : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: root.statusFilter === filterKey

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleStatusFilter(chip.filterKey)
    }
  }

  FileView {
    id: envFile
    path: Quickshell.env("HOME") + "/.config/omarqui/.env"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.parseEnv(text())
      envPermProc.command = ["chmod", "600", envFile.path]
      envPermProc.running = true
    }
    onLoadFailed: {
      root.apiKeyLoaded = true
      root.hasError = true
      root.errorText = "~/.config/omarqui/.env not found (see README)"
    }
  }

  // Enforces 0600 on the credential file every time it's (re-)loaded, since
  // it holds the Qui API key and nothing else guarantees its mode.
  Process {
    id: envPermProc
  }

  Process {
    id: statsProc
    stdinEnabled: true
    onStarted: {
      statsProc.write(root.apiKeyHeaderConfig())
      statsProc.stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleStats(text)
    }
    onExited: function(code) {
      if (code !== 0) {
        root.loading = false
        root.hasError = true
        root.errorText = "Qui unavailable at " + root.baseUrl
      }
    }
  }

  Process {
    id: instancesProc
    stdinEnabled: true
    onStarted: {
      instancesProc.write(root.apiKeyHeaderConfig())
      instancesProc.stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleInstances(text)
    }
  }

  Process {
    id: torrentsProc
    stdinEnabled: true
    onStarted: {
      torrentsProc.write(root.apiKeyHeaderConfig())
      torrentsProc.stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleTorrents(text)
    }
    onExited: function(code) {
      if (code !== 0) root.torrentsLoading = false
    }
  }

  Process {
    id: actionProc
    stdinEnabled: true
    onStarted: {
      actionProc.write(root.apiKeyHeaderConfig())
      actionProc.stdinEnabled = false
    }
    onExited: function(code) {
      root.actionInProgress = ""
      root.confirmDeleteHash = ""
      if (code === 0) {
        actionRefreshTimer.restart()
        actionRefreshTimer2.restart()
      }
    }
  }

  // qBittorrent/Qui take a moment to actually apply pause/resume/delete
  // before it shows up in the torrent list, so a single quick refetch
  // right after the request often still reads the old state. Refetch
  // twice: once past the typical ~1.5-2s lag, and once more as a safety
  // net for slower instances.
  Timer {
    id: actionRefreshTimer
    interval: 2000
    onTriggered: {
      root.fetchTorrents()
      root.refresh()
    }
  }

  Timer {
    id: actionRefreshTimer2
    interval: 4000
    onTriggered: {
      root.fetchTorrents()
      root.refresh()
    }
  }

  Process {
    id: categoriesProc
    stdinEnabled: true
    onStarted: {
      categoriesProc.write(root.apiKeyHeaderConfig())
      categoriesProc.stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleCategories(text)
    }
  }

  Process {
    id: addTorrentProc
    stdinEnabled: true
    onStarted: {
      addTorrentProc.write(root.apiKeyHeaderConfig())
      addTorrentProc.stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleAddTorrentResult(text)
    }
    onExited: function(code) {
      if (code !== 0) {
        root.addSubmitting = false
        root.addStatusError = true
        if (!root.addStatusText) root.addStatusText = "Failed to connect to Qui"
      }
    }
  }

  Timer {
    id: addSuccessTimer
    interval: 1200
    onTriggered: root.viewMode = "list"
  }

  Timer {
    id: pollTimer
    interval: root.pollInterval * 1000
    running: root.apiKeyLoaded
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
      if (root.opened) root.fetchTorrents()
    }
  }

  Timer {
    id: searchDebounce
    interval: 400
    onTriggered: root.fetchTorrents()
  }

  onOpenedChanged: {
    if (opened) {
      root.viewMode = "list"
      root.fetchTorrents()
    }
  }

  // Widest plausible "Both" text, used to size the bar chip so the
  // label never overflows its reserved slot into neighboring widgets.
  Text {
    id: bothWidthMetric
    visible: false
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    text: "↓ 999.9 M/s  ↑ 999.9 M/s"
  }

  // The Qui squirrel, drawn from the upstream logo paths on a 1024-unit grid
  // and scaled to the bar's icon canvas so it sits with the other bar glyphs.
  component QuiMark: Item {
    id: mark
    property real markSize: Style.bar.iconCanvas
    property color markColor: root.fg
    implicitWidth: markSize
    implicitHeight: markSize

    Shape {
      width: 1024
      height: 1024
      scale: mark.markSize / 1024
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer

      // Body, with the eye cut out of it.
      ShapePath {
        fillColor: mark.markColor
        strokeColor: mark.markColor
        strokeWidth: 30
        joinStyle: ShapePath.RoundJoin
        fillRule: ShapePath.OddEvenFill
        PathSvg { path: "M231.392 297.578c62.988-50.202 302.511-28.81 414.4-11.84 6.925-24.705 14.328-38.685 36.111-63.936-46.273-13.75-99.605-16.02-243.904-10.064-68.671-10.656-68.671-139.712 0-151.552 317.312 0 538.72 148 558.256 237.392 19.536 89.392 9.59 62.873 0 100.048-23.006 57.307-85.84 104.192-104.784 110.704-18.944 6.512-101.824 0-101.824 0-32.092 143.875-71.574 205.418-177.008 279.424-59.447 23.136-97.68 20.128-107.744-53.872l21.904-37.888 31.968-14.8c15.87-28.604 14.722-43.365 0-68.08-22.999-5.874-34.752-5.74-53.872 0-34.784 68.765-62.87 93.492-129.647 110.704v24.272l92.943 50.912 75.776 75.776c2.368 76.723-60.976 91.168-92.944 88.8C361.22 876.89 301.6 838.44 168.64 799.002c-26.486-5.732-30.057-15.395-23.088-40.256 58.775-115.1 40.65-183.322 23.088-213.712-29.558 30.414-99.602 83.694-140.896 0-46.2-93.636 61.568-113.862 117.808-110.704 2.368-24.666 22.85-86.55 85.84-136.752z M921.096 305.866a45.584 45.584 0 1 0 -91.168 0a45.584 45.584 0 1 0 91.168 0z" }
      }
      // Whiskers.
      ShapePath {
        fillColor: "transparent"
        strokeColor: mark.markColor
        strokeWidth: 84
        capStyle: ShapePath.RoundCap
        PathSvg { path: "M59.736 258.506h81.696M134.328 137.738h131.424" }
      }
    }
  }

  // Settings tile: a miniature of the bar showing exactly what a choice
  // draws, with a caption underneath. Paints its states like the kit Button.
  component SettingsTile: Rectangle {
    id: tile
    property string caption: ""
    property bool selected: false
    default property alias preview: previewSlot.data
    signal clicked()

    readonly property bool hot: tileMouse.containsMouse
    implicitHeight: tileColumn.implicitHeight + Style.space(12)
    radius: Style.cornerRadius
    color: tileMouse.pressed ? Style.pressedFillFor(root.fg, Color.accent)
      : hot ? Style.hoverFillFor(root.fg, Color.accent)
      : selected ? Style.selectedFillFor(root.fg, Color.accent)
      : "transparent"
    border.width: 1
    border.color: selected ? Color.accent : Util.alpha(root.fg, 0.18)

    ColumnLayout {
      id: tileColumn
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: Style.space(4)

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(30)
        radius: Style.cornerRadius
        color: root.bar ? root.bar.background : Color.background
        Item { id: previewSlot; anchors.fill: parent }
      }

      Text {
        Layout.fillWidth: true
        text: tile.caption
        horizontalAlignment: Text.AlignHCenter
        color: tile.selected ? root.fg : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.clicked()
    }
  }

  // Colour chip for the tint picker: a swatch square with its name.
  component SwatchChip: Rectangle {
    id: chip
    property string label: ""
    property color swatch: root.fg
    property bool selected: false
    signal clicked()

    readonly property bool hot: chipMouse.containsMouse
    implicitWidth: chipRow.implicitWidth + Style.space(16)
    implicitHeight: chipRow.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: chipMouse.pressed ? Style.pressedFillFor(root.fg, Color.accent)
      : hot ? Style.hoverFillFor(root.fg, Color.accent)
      : selected ? Style.selectedFillFor(root.fg, Color.accent)
      : "transparent"
    border.width: 1
    border.color: selected ? Color.accent : Util.alpha(root.fg, 0.18)

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Rectangle {
        width: Style.space(12); height: Style.space(12); radius: 2
        anchors.verticalCenter: parent.verticalCenter
        color: chip.swatch
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        color: chip.selected ? root.fg : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // Small arrow on a 6-unit grid. `halo` paints a disc in the bar colour
  // behind it so it stays readable where it overlaps the mark's tail.
  component QuiArrow: Item {
    id: arrow
    property bool up: false
    property color color: root.fg
    property bool halo: false
    property color haloColor: "transparent"
    property real unit: 1
    implicitWidth: 6 * unit
    implicitHeight: 6 * unit

    Shape {
      width: 6
      height: 6
      scale: arrow.unit
      transformOrigin: Item.TopLeft
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: arrow.halo ? arrow.haloColor : "transparent"
        strokeColor: "transparent"
        strokeWidth: 0
        PathSvg { path: "M7 3a4 4 0 1 0 -8 0a4 4 0 1 0 8 0z" }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: arrow.color
        strokeWidth: 1.4
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: arrow.up ? "M3 5.3V.7M1 2.6 3 .7l2 1.9" : "M3 .7v4.6M1 3.4 3 5.3l2-1.9" }
      }
    }
  }

  // The bar logo with its activity treatment. Geometry is laid out on the
  // 16-unit icon canvas and scaled by `size`, so the settings tiles and the
  // bar draw the exact same thing.
  component QuiLogo: Item {
    id: logo
    property string activity: "Static"
    property string arrowColor: "Bar"
    property color tint: root.fg
    property bool downActive: false
    property bool upActive: false
    property color color: root.fg
    property color haloColor: "transparent"
    property real size: Style.bar.iconCanvas
    // Vertical room the logo is centred in (0 = unconstrained). Only the
    // underline reaches past the mark, and it is clamped to stay inside.
    property real availableHeight: 0

    readonly property real u: size / 16
    readonly property bool active: downActive || upActive
    readonly property bool beside: activity === "BesideUpDown" || activity === "BesideDownUp"
    // State colours pick their light-surface variant from the mark colour:
    // a dark mark means a light background behind it.
    readonly property color downMark: arrowColor === "State" ? root.downColorFor(color) : color
    readonly property color upMark: arrowColor === "State" ? root.upColorFor(color) : color
    readonly property color offMark: Util.alpha(color, 0.3)

    implicitWidth: size + (beside ? 9 * u : 0)
    implicitHeight: size

    property real pulsePhase: 1.0
    SequentialAnimation on pulsePhase {
      running: logo.activity === "Pulse" && logo.active
      loops: Animation.Infinite
      NumberAnimation { from: 1.0; to: 0.45; duration: 800; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.45; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
      onRunningChanged: if (!running) logo.pulsePhase = 1.0
    }

    // Drift runs one arrow at a time. The sweep is a fixed 2.8 s cycle and
    // `driftCycle` alternates which direction owns it, so a direction that
    // starts or stops mid-sweep takes effect at once — a duration bound to
    // downActive/upActive would only apply on the next loop.
    property real driftT: 0
    property int driftCycle: 0
    SequentialAnimation {
      running: logo.activity === "Drift" && logo.active
      loops: Animation.Infinite
      NumberAnimation { target: logo; property: "driftT"; from: 0; to: 1; duration: 2800 }
      ScriptAction { script: logo.driftCycle = (logo.driftCycle + 1) % 2 }
      onRunningChanged: if (!running) { logo.driftT = 0; logo.driftCycle = 0 }
    }
    function driftPhase(isUp) {
      if (isUp ? !logo.upActive : !logo.downActive) return -1
      if (logo.downActive && logo.upActive)
        return logo.driftCycle === (isUp ? 1 : 0) ? logo.driftT : -1
      return logo.driftT
    }
    function driftOpacity(p) {
      if (p < 0) return 0
      return p < 0.3 ? p / 0.3 * 0.85 : (1 - p) / 0.7 * 0.85
    }
    function driftOffset(p, isUp) {
      if (p < 0) return 0
      var d = (p * 2 - 1) * 1.5 * logo.u
      return isUp ? -d : d
    }
    readonly property real driftDown: driftPhase(false)
    readonly property real driftUp: driftPhase(true)

    QuiMark {
      markSize: logo.size
      markColor: logo.activity === "Tint" && logo.active ? logo.tint : logo.color
      opacity: logo.activity === "Pulse" ? logo.pulsePhase
        : logo.activity === "Dim" ? (logo.active ? 1.0 : 0.42)
        : 1.0
    }

    // Underline halves. They sit 2 units below the 16-unit mark, which needs
    // 24 units of bar to show; on a shorter bar they slide up against the
    // mark instead of being clipped away.
    readonly property real underlineY: logo.availableHeight > 0
      ? Math.min(18 * logo.u, (logo.availableHeight + logo.size) / 2 - 2 * logo.u)
      : 18 * logo.u
    Rectangle {
      visible: logo.activity === "Underline"
      x: 1 * logo.u; y: logo.underlineY; width: 6 * logo.u; height: 2 * logo.u; radius: logo.u
      color: logo.downMark
      opacity: logo.downActive ? 1 : 0
    }
    Rectangle {
      visible: logo.activity === "Underline"
      x: 9 * logo.u; y: logo.underlineY; width: 6 * logo.u; height: 2 * logo.u; radius: logo.u
      color: logo.upMark
      opacity: logo.upActive ? 1 : 0
    }

    // Corner arrows.
    QuiArrow {
      visible: logo.activity === "Corners"
      x: -2 * logo.u; y: 12 * logo.u; unit: logo.u
      color: logo.downMark; halo: true; haloColor: logo.haloColor
      opacity: logo.downActive ? 1 : 0
    }
    QuiArrow {
      visible: logo.activity === "Corners"
      up: true
      x: 12 * logo.u; y: 12 * logo.u; unit: logo.u
      color: logo.upMark; halo: true; haloColor: logo.haloColor
      opacity: logo.upActive ? 1 : 0
    }

    // Arrow column beside the mark, always present, lit per direction.
    QuiArrow {
      visible: logo.beside
      up: logo.activity === "BesideUpDown"
      x: 19 * logo.u; y: 1 * logo.u; unit: logo.u
      color: up ? (logo.upActive ? logo.upMark : logo.offMark) : (logo.downActive ? logo.downMark : logo.offMark)
    }
    QuiArrow {
      visible: logo.beside
      up: logo.activity === "BesideDownUp"
      x: 19 * logo.u; y: 9 * logo.u; unit: logo.u
      color: up ? (logo.upActive ? logo.upMark : logo.offMark) : (logo.downActive ? logo.downMark : logo.offMark)
    }

    // Quiet drift.
    QuiArrow {
      visible: logo.activity === "Drift"
      x: 13 * logo.u; y: 13 * logo.u + logo.driftOffset(logo.driftDown, false); unit: logo.u
      color: logo.downMark; halo: true; haloColor: logo.haloColor
      opacity: logo.driftOpacity(logo.driftDown)
    }
    QuiArrow {
      visible: logo.activity === "Drift"
      up: true
      x: 13 * logo.u; y: 13 * logo.u + logo.driftOffset(logo.driftUp, true); unit: logo.u
      color: logo.upMark; halo: true; haloColor: logo.haloColor
      opacity: logo.driftOpacity(logo.driftUp)
    }
  }

  BarIconButton {
    id: logoButton
    anchors.fill: parent
    visible: root.showLogo
    bar: root.bar
    // The arrow column widens the slot, and BarIconButton maps slotSize to
    // height on a vertical bar, where the extra width buys nothing.
    slotSize: Style.bar.iconSlot + (root.bar && root.bar.vertical ? 0 : root.logoExtraWidth)
    tooltipText: button.tooltipText
    iconComponent: Component {
      Item {
        QuiLogo {
          anchors.centerIn: parent
          activity: root.hasError ? "Static" : root.logoActivity
          arrowColor: root.arrowColor
          tint: root.resolveTint(root.tintColor)
          // Gated on showLogo as well: this button is still instantiated in
          // Speed style, and an ungated Pulse would animate behind it.
          downActive: root.showLogo && root.downloading
          upActive: root.showLogo && root.uploading
          color: root.logoMarkColor
          haloColor: root.logoHaloColor
          availableHeight: root.logoBarHeight
        }
      }
    }
    onPressed: function(b) { root.triggerPress(b) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    visible: !root.showLogo
    bar: root.bar
    text: root.hasError
      ? root.barIcon + " !"
      : root.barText()
    fixedWidth: root.bar && root.bar.vertical ? -1 : (root.barMetric === "Both" ? (bothWidthMetric.implicitWidth + Style.spaceReal(17)) : Style.space(78))
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    tooltipText: root.hasError
      ? root.errorText
      : ("↓ " + root.formatSpeed(root.stats.totalDownloadSpeed)
        + "   ↑ " + root.formatSpeed(root.stats.totalUploadSpeed)
        + "\n" + (root.stats.downloading || 0) + " downloading · "
        + (root.stats.seeding || 0) + " seeding")
    onPressed: function(b) { root.triggerPress(b) }
  }

  implicitWidth: root.showLogo ? logoButton.implicitWidth : button.implicitWidth
  implicitHeight: root.showLogo ? logoButton.implicitHeight : button.implicitHeight

  KeyboardPanel {
    id: panel
    anchorItem: root.showLogo ? logoButton : button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, root.panelMaxHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || sourceField.activeFocus || baseUrlField.activeFocus || root.tintFieldFocused
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") { root.refresh(); root.fetchTorrents() }
        if (root.viewMode !== "list") return
        if (t === "a" || t === "A") root.openAddView()
        if (t === "s" || t === "S") root.openSettingsView()
      }

      ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        RowLayout {
          id: headerRow
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: root.barIcon + "  " + (root.viewMode === "add" ? "Add torrent" : root.viewMode === "settings" ? "Settings" : "Qui Torrents")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          Button {
            visible: root.viewMode === "list"
            text: "+ Add"
            foreground: root.fg
            accent: Color.accent
            tooltipText: "Add a new torrent"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.openAddView()
          }

          Button {
            visible: root.viewMode === "list"
            text: (root.loading || root.torrentsLoading) ? "Refreshing…" : "Refresh"
            foreground: root.fg
            tooltipText: "Refresh now"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            active: root.loading || root.torrentsLoading
            onClicked: { root.refresh(); root.fetchTorrents() }
          }

          Button {
            visible: root.viewMode === "list"
            text: "⚙"
            foreground: root.fg
            tooltipText: "Settings"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.openSettingsView()
          }

          Button {
            visible: root.viewMode === "add" || root.viewMode === "settings"
            text: "Back"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.viewMode === "settings" ? root.closeSettingsView() : root.closeAddView()
          }
        }

        // Settings: one tab per group so new options land in a group
        // instead of stretching one long list. Everything applies on change.
        ButtonGroup {
          id: settingsTabs
          visible: root.viewMode === "settings"
          options: [
            { value: "connection", label: "Connection" },
            { value: "bar", label: "Bar" }
          ]
          value: root.settingsTab
          foreground: root.fg
          accent: Color.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          focusable: false
          onChanged: function(v) { root.settingsTab = v }
        }

        Flickable {
          id: settingsFlick
          visible: root.viewMode === "settings"
          Layout.fillWidth: true
          // Takes whatever the card has left after the header, the tabs and
          // the footer hint, so the two caps cannot drift apart and overflow
          // the card at a large font scale.
          readonly property real chrome: headerRow.implicitHeight + settingsTabs.implicitHeight
            + footerHint.implicitHeight + contentColumn.spacing * 3
          readonly property real cap: Math.max(Style.space(120),
            Math.min(root.panelMaxHeight,
              panel.availableCardHeight > 0 ? panel.availableCardHeight : root.panelMaxHeight)
            - panel.verticalContentInset - chrome)
          Layout.preferredHeight: Math.min(settingsColumn.implicitHeight, cap)
          contentWidth: width
          contentHeight: settingsColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          ColumnLayout {
            id: settingsColumn
            width: settingsFlick.width
            spacing: Style.space(10)

            // ---- Connection ----
            ColumnLayout {
              visible: root.settingsTab === "connection"
              Layout.fillWidth: true
              spacing: Style.space(10)

              Text {
                text: "Qui base URL"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // Bound rather than seeded on open, so a change made elsewhere
              // shows up here. Typing breaks the binding (which is what keeps
              // an edit in progress safe); committing restores it.
              TextField {
                id: baseUrlField
                Layout.fillWidth: true
                placeholderText: "http://localhost:7476"
                foreground: root.fg
                text: root.baseUrl
                onEditingFinished: {
                  root.commitBaseUrl(text)
                  text = Qt.binding(function() { return root.baseUrl })
                }
              }

              NumberField {
                label: "Refresh interval (seconds)"
                value: root.pollInterval
                from: 5
                to: 300
                stepSize: 5
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.setRefreshInterval(v) }
              }

              Text {
                Layout.fillWidth: true
                text: "The API key stays in ~/.config/omarqui/.env and is not editable here."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Text {
                Layout.fillWidth: true
                text: "Tip: disabling and re-enabling the plugin resets this field. Add BASE_URL=... to ~/.config/omarqui/.env to keep a fallback that survives that."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            // ---- Bar ----
            // Nine live logo previews are not cheap, and the whole settings
            // tree is built per screen at shell start, so the tab is only
            // instantiated once it is actually looked at.
            Loader {
              id: barTab
              active: root.settingsTab === "bar"
              visible: active
              Layout.fillWidth: true

              sourceComponent: ColumnLayout {
                spacing: Style.space(10)

                Text {
                  text: "Show on the bar"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                GridLayout {
                  Layout.fillWidth: true
                  columns: 2
                  columnSpacing: Style.space(6)
                  rowSpacing: Style.space(6)

                  SettingsTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    caption: "Speed"
                    selected: root.barStyle === "Speed"
                    onClicked: root.persistSettings({ barStyle: "Speed" })
                    Text {
                      anchors.centerIn: parent
                      text: "↓ 2.4 M/s"
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  SettingsTile {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    caption: "Logo"
                    selected: root.barStyle === "Logo"
                    onClicked: root.persistSettings({ barStyle: "Logo" })
                    QuiLogo {
                      anchors.centerIn: parent
                      color: root.barForeground
                      haloColor: root.logoHaloColor
                    }
                  }
                }

                // Speed: which number the chip shows.
                Text {
                  visible: !root.showLogo
                  text: "Metric"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                GridLayout {
                  visible: !root.showLogo
                  Layout.fillWidth: true
                  columns: 3
                  columnSpacing: Style.space(6)
                  rowSpacing: Style.space(6)

                  Repeater {
                    model: [
                      { key: "Download", sample: "↓ 2.4 M/s" },
                      { key: "Upload", sample: "↑ 310 K/s" },
                      { key: "Both", sample: "↓ 2.4 M ↑ 310 K" }
                    ]
                    delegate: SettingsTile {
                      required property var modelData
                      Layout.fillWidth: true
                      Layout.preferredWidth: 1
                      caption: modelData.key
                      selected: root.barMetric === modelData.key
                      onClicked: root.persistSettings({ barMetric: modelData.key })
                      Text {
                        anchors.centerIn: parent
                        text: modelData.sample
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                // Logo: every tile is the real mark with both directions
                // active, painted from the same colours the bar uses, so each
                // treatment shows what it actually does up there.
                Text {
                  visible: root.showLogo
                  text: "While transferring"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                GridLayout {
                  visible: root.showLogo
                  Layout.fillWidth: true
                  columns: 3
                  columnSpacing: Style.space(6)
                  rowSpacing: Style.space(6)

                  Repeater {
                    model: root.activityKeys
                    delegate: SettingsTile {
                      id: activityTile
                      required property string modelData
                      Layout.fillWidth: true
                      Layout.preferredWidth: 1
                      caption: root.activityLabel(modelData)
                      selected: root.logoActivity === modelData
                      onClicked: root.persistSettings({ logoActivity: modelData })
                      QuiLogo {
                        anchors.centerIn: parent
                        activity: activityTile.modelData
                        arrowColor: root.arrowColor
                        tint: root.resolveTint(root.tintColor)
                        // Dim is the one treatment whose point is the idle
                        // look. Gated on this tab being on screen so Pulse
                        // and Drift never animate out of sight.
                        downActive: root.logoTilesLive && activityTile.modelData !== "Dim"
                        upActive: root.logoTilesLive && activityTile.modelData !== "Dim"
                        color: root.barForeground
                        haloColor: root.logoHaloColor
                      }
                    }
                  }
                }

                Text {
                  visible: root.showLogo
                  Layout.fillWidth: true
                  text: root.activityDescription(root.logoActivity)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                // Direction treatments: arrows in the bar colour or the state colours.
                Text {
                  visible: root.showLogo && root.isDirectionActivity(root.logoActivity)
                  text: "Arrow colour"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                GridLayout {
                  visible: root.showLogo && root.isDirectionActivity(root.logoActivity)
                  Layout.fillWidth: true
                  columns: 2
                  columnSpacing: Style.space(6)
                  rowSpacing: Style.space(6)

                  Repeater {
                    model: [
                      { key: "Bar", label: "Bar colour" },
                      { key: "State", label: "Down blue · Up green" }
                    ]
                    delegate: SettingsTile {
                      id: arrowTile
                      required property var modelData
                      Layout.fillWidth: true
                      Layout.preferredWidth: 1
                      caption: modelData.label
                      selected: root.arrowColor === modelData.key
                      onClicked: root.persistSettings({ arrowColor: modelData.key })
                      Row {
                        anchors.centerIn: parent
                        spacing: Style.space(6)
                        QuiArrow {
                          unit: Style.bar.iconCanvas / 16 * 1.4
                          color: arrowTile.modelData.key === "State" ? root.logoDownColor : root.barForeground
                        }
                        QuiArrow {
                          up: true
                          unit: Style.bar.iconCanvas / 16 * 1.4
                          color: arrowTile.modelData.key === "State" ? root.logoUpColor : root.barForeground
                        }
                      }
                    }
                  }
                }

                // Tint: the colour the mark takes while transferring.
                Text {
                  visible: root.showLogo && root.logoActivity === "Tint"
                  text: "Active colour"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Flow {
                  visible: root.showLogo && root.logoActivity === "Tint"
                  Layout.fillWidth: true
                  spacing: Style.space(6)

                  Repeater {
                    model: root.tintPresets
                    delegate: SwatchChip {
                      required property var modelData
                      label: modelData.label
                      swatch: modelData.key === "custom"
                        ? (root.isHexColor(root.customTint) ? root.customTint : root.dim)
                        : root.resolveTint(modelData.key)
                      selected: root.tintChoice === modelData.key
                      onClicked: root.selectTint(modelData.key)
                    }
                  }
                }

                RowLayout {
                  visible: root.showLogo && root.logoActivity === "Tint" && root.tintChoice === "custom"
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  // Bound to the working value, which is also what
                  // commitCustomTint() reads: this field is inside a Loader,
                  // so its id is not reachable from the panel's functions.
                  TextField {
                    id: hexField
                    Layout.preferredWidth: Style.space(120)
                    placeholderText: "#rrggbb"
                    foreground: root.fg
                    text: root.customTint
                    onTextEdited: {
                      root.customTint = text
                      text = Qt.binding(function() { return root.customTint })
                    }
                    onEditingFinished: root.commitCustomTint()
                    onActiveFocusChanged: root.tintFieldFocused = activeFocus
                    Component.onDestruction: root.tintFieldFocused = false
                  }

                  Text {
                    Layout.fillWidth: true
                    text: root.hexStatusText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }

            Text {
              visible: root.settingsStatusText !== ""
              Layout.fillWidth: true
              text: root.settingsStatusText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }

        ColumnLayout {
          visible: root.viewMode === "add"
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            text: "Instance"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
              model: root.instances
              delegate: Button {
                required property var modelData
                text: modelData.name
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                selected: root.addInstanceId === modelData.id
                onClicked: root.selectAddInstance(modelData.id)
              }
            }
          }

          Dropdown {
            Layout.fillWidth: true
            label: "Category"
            value: root.addCategory
            options: [{ value: "", label: "No category" }].concat(root.categories)
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFamily
            onChanged: function(v) { root.addCategory = v }
          }

          TextField {
            id: sourceField
            Layout.fillWidth: true
            placeholderText: "magnet:?xt=... or ~/Downloads/file.torrent"
            foreground: root.fg
            text: root.addSource
            onTextChanged: root.addSource = text
          }

          RowLayout {
            spacing: 8
            ToggleSwitch {
              foreground: root.fg
              accent: Color.accent
              checked: root.addPaused
              onToggled: root.addPaused = !root.addPaused
            }
            Text {
              text: "Start paused"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: root.addStatusText !== ""
            Layout.fillWidth: true
            text: root.addStatusText
            color: root.addStatusError ? Color.urgent : "#8fd694"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            text: root.addSubmitting ? "Adding…" : "Add torrent"
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            active: root.addSubmitting
            onClicked: root.submitAddTorrent()
          }

          Text {
            Layout.fillWidth: true
            text: "Paste a magnet link, or provide the path to a local .torrent file (e.g. ~/Downloads/name.torrent)."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          visible: root.hasError && root.viewMode === "list"
          text: root.errorText
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        RowLayout {
          visible: !root.hasError && root.viewMode === "list"
          Layout.fillWidth: true
          spacing: Style.space(24)

          ColumnLayout {
            spacing: 2
            Text {
              text: root.formatSpeed(root.stats.totalDownloadSpeed)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: "download"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          ColumnLayout {
            spacing: 2
            Text {
              text: root.formatSpeed(root.stats.totalUploadSpeed)
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: "upload"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        RowLayout {
          visible: !root.hasError && root.viewMode === "list"
          Layout.fillWidth: true
          spacing: 4

          StatChip { filterKey: "active"; label: "active"; count: root.activeCount }
          Text { text: "·"; color: root.dim; font.pixelSize: Style.font.caption }
          StatChip { filterKey: "downloading"; label: "downloading"; count: root.stats.downloading || 0 }
          Text { text: "·"; color: root.dim; font.pixelSize: Style.font.caption }
          StatChip { filterKey: "seeding"; label: "seeding"; count: root.stats.seeding || 0 }
          Text { text: "·"; color: root.dim; font.pixelSize: Style.font.caption }
          StatChip { filterKey: "paused"; label: "paused"; count: root.stats.paused || 0 }
          Text {
            visible: (root.stats.error || 0) > 0 || root.statusFilter === "error"
            text: "·"
            color: root.dim
            font.pixelSize: Style.font.caption
          }
          StatChip {
            visible: (root.stats.error || 0) > 0 || root.statusFilter === "error"
            filterKey: "error"
            label: "errored"
            count: root.stats.error || 0
          }
          Item { Layout.fillWidth: true }
        }

        Flow {
          visible: !root.hasError && root.viewMode === "list"
          Layout.fillWidth: true
          Layout.topMargin: 4
          spacing: 6

          Button {
            text: "All"
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            selected: root.selectedInstanceId === -1
            onClicked: root.selectInstance(-1)
          }

          Repeater {
            model: root.instances
            delegate: Button {
              required property var modelData
              text: (modelData.connected ? "● " : "○ ") + modelData.name
              foreground: modelData.connected ? root.fg : Color.urgent
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              selected: root.selectedInstanceId === modelData.id
              onClicked: root.selectInstance(modelData.id)
            }
          }
        }

        TextField {
          id: searchField
          visible: root.viewMode === "list"
          Layout.fillWidth: true
          placeholderText: "Search torrents…"
          foreground: root.fg
          text: root.searchQuery
          onTextChanged: { root.searchQuery = text; searchDebounce.restart() }
          Keys.onEscapePressed: text = ""
        }

        Text {
          visible: root.viewMode === "list" && !root.torrentsLoading && root.torrents.length === 0
          Layout.fillWidth: true
          Layout.topMargin: 8
          horizontalAlignment: Text.AlignHCenter
          text: root.rawTorrents.length === 0 ? "No torrents found" : "No torrents match the filter"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        ListView {
          id: torrentList
          visible: root.viewMode === "list" && root.torrents.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(360)
          clip: true
          spacing: Style.space(8)
          model: root.torrents
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: ColumnLayout {
            id: row
            required property var modelData
            width: torrentList.width
            height: implicitHeight
            spacing: 3

            readonly property bool confirming: root.confirmDeleteHash === modelData.hash
            readonly property bool busy: root.actionInProgress.indexOf(modelData.hash + ":") === 0

            Text {
              Layout.fillWidth: true
              text: row.modelData.name
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Rectangle {
              Layout.fillWidth: true
              height: 4
              radius: 2
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0, Math.min(1, row.modelData.progress || 0))
                radius: 2
                color: root.stateColor(row.modelData.state)
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Text {
                text: root.stateLabel(row.modelData.state) + " · "
                  + Math.round((row.modelData.progress || 0) * 100) + "% · "
                  + root.formatBytes(row.modelData.size)
                  + " · " + (Number(row.modelData.ratio) || 0).toFixed(2)
                  + (row.modelData.dlspeed > 0 ? " · ↓" + root.formatSpeed(row.modelData.dlspeed) : "")
                  + (row.modelData.upspeed > 0 ? " · ↑" + root.formatSpeed(row.modelData.upspeed) : "")
                color: root.stateColor(row.modelData.state)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              RowLayout {
                visible: !row.confirming
                spacing: 4

                Button {
                  text: row.busy ? "…" : (root.isPaused(row.modelData.state) ? "Resume" : "Pause")
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: {
                    if (row.busy) return
                    root.torrentAction(row.modelData, root.isPaused(row.modelData.state) ? "resume" : "pause")
                  }
                }

                Button {
                  text: "Delete"
                  foreground: Color.urgent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: { if (!row.busy) root.confirmDeleteHash = row.modelData.hash }
                }
              }

              RowLayout {
                visible: row.confirming
                spacing: 4

                Text {
                  text: "Delete:"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Button {
                  text: "keep files"
                  foreground: Color.urgent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: root.torrentAction(row.modelData, "delete")
                }
                Button {
                  text: "+ files"
                  foreground: Color.urgent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: root.torrentAction(row.modelData, "deleteWithFiles")
                }
                Button {
                  text: "cancel"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: root.confirmDeleteHash = ""
                }
              }
            }
          }
        }

        Text {
          id: footerHint
          Layout.fillWidth: true
          Layout.topMargin: 4
          text: "r refresh · a add · s settings · esc close"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
