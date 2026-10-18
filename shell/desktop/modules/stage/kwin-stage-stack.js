// Keep the Stage Manager strip above the desktop-widget surface.
//
// Both are fullscreen quickshell windows on KWin's Below layer. Within a
// layer there is no persistent rank: KWin appends newly mapped surfaces to
// the top and raises a window when it is activated. The widget surface has
// keyboardFocus OnDemand, so right-clicking the desktop activates it and
// raises it above the strip; a late widget remap does the same. Watch the
// layer order and re-raise the strip whenever the widget ends up on top.
// Re-raising existing surfaces does not recreate them, so nothing flickers.
//
// The two windows differ only in their layer-shell keyboard mode:
//   DeskCenter: keyboardFocus OnDemand -> wantsInput true
//   Strip:      keyboardFocus None     -> wantsInput false
//   Wallpaper:  windowType Desktop
// The modes are pinned in DeskCenterWindow.qml / StageSidebarWindow.qml; do
// not change them without updating this script.
const BELOW_LAYER = 1

let reordering = false

function isShellSurface(w) {
  return !!w && w.layer === BELOW_LAYER
    && w.resourceClass === "quickshell"
    && w.windowType === 0
}

function eachShell(fn) {
  const list = workspace.stackingOrder
  for (let i = 0; i < list.length; ++i) {
    if (isShellSurface(list[i]))
      fn(list[i])
  }
}

function stripIsCovered() {
  let stripTop = -1
  let widgetTop = -1
  eachShell(function (w) {
    if (w.wantsInput)
      widgetTop = Math.max(widgetTop, w.stackingOrder)
    else
      stripTop = Math.max(stripTop, w.stackingOrder)
  })
  return stripTop >= 0 && widgetTop > stripTop
}

function raiseStrips() {
  if (reordering)
    return
  reordering = true
  eachShell(function (w) {
    if (!w.wantsInput)
      workspace.raiseWindow(w)
  })
  reordering = false
}

function ensureOrder() {
  if (stripIsCovered())
    raiseStrips()
}

workspace.windowAdded.connect(function (w) {
  if (!isShellSurface(w))
    return
  w.stackingOrderChanged.connect(ensureOrder)
  ensureOrder()
})

eachShell(function (w) {
  w.stackingOrderChanged.connect(ensureOrder)
})
ensureOrder()
