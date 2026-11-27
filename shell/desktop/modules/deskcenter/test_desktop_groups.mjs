import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CATEGORY_ORDER, buildGroups, categoryOf, iconName, labelKey }
    from './DesktopGroups.mjs';

// The four preset categories and their fixed display order.
assert.deepEqual(CATEGORY_ORDER, ['shortcuts', 'pictures', 'folders', 'files']);

// Known kinds map to their own category; every other kind is a file.
assert.equal(categoryOf('launcher'), 'shortcuts');
assert.equal(categoryOf('image'), 'pictures');
assert.equal(categoryOf('folder'), 'folders');
for (const kind of ['file', 'pdf', 'text', 'code', 'video', 'archive', '', undefined])
    assert.equal(categoryOf(kind), 'files', `fallback for ${String(kind)}`);

// Display labels stay stable source strings for I18n.
assert.equal(labelKey('shortcuts'), 'App shortcuts');
assert.equal(labelKey('pictures'), 'Pictures');
assert.equal(labelKey('folders'), 'Folders');
assert.equal(labelKey('files'), 'Files');
assert.equal(labelKey('unknown'), '');

// Each tab has a bundled glyph that exists in the shell's icon map.
assert.equal(iconName('shortcuts'), 'desktop.file.launcher');
assert.equal(iconName('pictures'), 'desktop.file.image');
assert.equal(iconName('folders'), 'desktop.file.folder');
assert.equal(iconName('files'), 'desktop.file.text');
assert.equal(iconName('unknown'), 'desktop.file.text');

// Empty categories disappear, and the remaining groups keep the preset order.
const entries = [
    { path: '/d/report.pdf', kind: 'pdf' },
    { path: '/d/photo.png', kind: 'image' },
    { path: '/d/App.desktop', kind: 'launcher' },
    { path: '/d/Projects', kind: 'folder' },
    { path: '/d/notes.txt', kind: 'text' },
    { path: '/d/photo2.jpg', kind: 'image' }
];
const groups = buildGroups(entries);
assert.deepEqual(groups.map(group => group.category),
    ['shortcuts', 'pictures', 'folders', 'files']);
assert.deepEqual(groups[0].entries.map(entry => entry.path), ['/d/App.desktop']);
assert.deepEqual(groups[1].entries.map(entry => entry.path),
    ['/d/photo.png', '/d/photo2.jpg']);
assert.deepEqual(groups[2].entries.map(entry => entry.path), ['/d/Projects']);
assert.deepEqual(groups[3].entries.map(entry => entry.path),
    ['/d/report.pdf', '/d/notes.txt']);

// Only non-empty categories are returned.
assert.deepEqual(buildGroups([{ path: '/d/photo.png', kind: 'image' }])
    .map(group => group.category), ['pictures']);
assert.deepEqual(buildGroups([]), []);
assert.deepEqual(buildGroups(null), []);

// Building groups never mutates the caller's entries.
const untouched = entries.slice();
buildGroups(entries);
assert.deepEqual(entries, untouched);
assert.notEqual(buildGroups(entries)[3].entries, entries[3]);

// ── QML wiring ──
// The pure mapping only matters if the widget definition, visibility, menu,
// content loader and the normal grid's visibility stay connected.
const qml = name => readFileSync(new URL('./' + name, import.meta.url), 'utf8');
const deskcenter = qml('DeskCenterWindow.qml');
const service = qml('DesktopFilesService.qml');
const view = qml('DesktopGroupsContent.qml');
const deskwidget = qml('DeskWidgetCard.qml');
const memberIcon = qml('DesktopGroupMemberIcon.qml');
const config = qml('DeskCenterConfigService.qml');
const layout = qml('WidgetLayout.mjs');
const qmldir = qml('qmldir');

assert.match(service, /property string groupSelectedCategory: "shortcuts"/);
assert.match(service, /function setGroupSelectedCategory\(category\)/);
assert.ok(!service.includes('groupByType'), 'widget visibility owns the mode');
assert.ok(!service.includes('groupPanelJson'), 'widget layout owns the geometry');
assert.match(service, /function pasteImageToDesktop\(output\)/);
assert.match(service, /"clipboard\.save-image"/);
assert.match(service, /I18n\.tr\("Clipboard image"\)/);
assert.match(service, /No files or images to paste in the clipboard/);
assert.match(deskcenter,
    /_ctxCheck\(I18n\.tr\("Grouped View"\), "toggleGroupsWidget"/);
assert.match(deskcenter, /case "toggleGroupsWidget": \{/);
assert.match(deskcenter,
    /AppearanceConfigService\.setDeskCenterWidgetVisible\("groups"/);
assert.match(deskcenter, /readonly property bool groupsWidgetVisible/);
assert.match(deskcenter, /readonly property bool groupsWidgetShown/);
assert.match(deskcenter,
    /visible: !root\.groupsWidgetShown/,
    'the normal icon surface must hide while the groups widget is shown');
assert.match(deskcenter, /enabled: root\.groupsWidgetShown/);
assert.match(deskcenter, /groupsWidgetDefinition/);
assert.match(deskcenter, /flowWidgetDefinitions/);
assert.match(deskcenter, /flowWidgetLayout/);
assert.match(deskcenter, /groupsPlacement/);
assert.match(deskcenter, /WidgetLayout\.placeAnchoredWidget/);
assert.match(deskcenter, /WidgetLayout\.insetRightEdge\(/,
    'the anchored card keeps the visible right margin');
assert.match(deskcenter, /WidgetLayout\.maxSpanFor/);
assert.match(deskcenter, /maxDropColumns/);
assert.match(deskcenter, /allowColorArtwork: modelData\.id !== "groups"/);
assert.match(deskcenter, /card\.modelData\.id === "groups"/);
assert.match(deskcenter, /DesktopGroupsContent \{/);
// Editing chrome lives in the floating WidgetGalleryWindow (driven by
// WidgetGalleryService) anchored along the free bottom edge, independent of the
// top-right grouped card.
assert.match(deskcenter, /WidgetGalleryService\.show\(root\.screen\)/);
assert.match(deskcenter, /readonly property real galleryX:/);
assert.match(deskcenter, /readonly property real galleryY:/);

assert.ok(!deskcenter.includes('DesktopGroupsView'),
    'the standalone view is replaced by the widget content');
assert.ok(!deskcenter.includes('desktopGroupsView.blurRegion'),
    'the widget blur union already includes the card');
assert.ok(!qmldir.includes('DesktopGroupsView'));
assert.match(qmldir, /DesktopGroupsContent 1\.0 DesktopGroupsContent\.qml/);

assert.match(config, /groups: "medium"/);
assert.match(config, /"groups"/);
assert.match(layout, /groups: \{ small: \[2, 2\], medium: \[2, 3\], large: \[3, 3\] \}/);
assert.match(layout, /export function placeAnchoredWidget/);
assert.match(layout, /export function maxSpanFor/);
assert.match(layout, /export function minSpanFor/);
assert.match(layout, /\["2x2", "2x3", "3x2", "3x3"\]/,
    'the grouped view offers only its four readable spans');
assert.match(deskcenter, /WidgetLayout\.minSpanFor/);
assert.match(deskcenter, /readonly property var sizeLimit:[\s\S]*?WidgetLayout\.maxSpanFor/);
assert.match(deskcenter, /readonly property var sizeFloor:[\s\S]*?WidgetLayout\.minSpanFor/);
assert.match(deskcenter, /maximumColumns: card\.sizeLimit\[0\]/);
assert.match(deskcenter, /maximumRows: card\.sizeLimit\[1\]/);
assert.match(deskcenter, /minimumColumns: card\.sizeFloor\[0\]/);
assert.match(deskcenter, /minimumRows: card\.sizeFloor\[1\]/);

assert.match(view, /DesktopGroups\.buildGroups\(entries\)/);
assert.match(view, /^Item \{/m);
assert.match(view, /property bool editing: false/);
assert.match(view, /DesktopGroups\.CATEGORY_ORDER/);
assert.match(view, /function selectCategory\(category\)/);
assert.match(view, /signal categorySelected\(string category\)/);
assert.match(view, /ListModel \{ id: contentModel \}/);
assert.ok(!view.includes('PanelGeometry'), 'widget layout owns the geometry');
assert.ok(!view.includes('geometryCommitted'), 'widget layout owns resize');
assert.ok(!view.includes('availableWidth'), 'the widget delegate owns size');
assert.ok(!view.includes('DragHandler'), 'widget edit mode owns moving');
assert.match(view, /name: "search\.query"/);
assert.match(view, /function openSearch\(\)/);
assert.match(view, /function closeSearch\(\)/);
assert.match(view, /function entryMatches\(entry\)/);
assert.match(view, /root\.entryMatches\(entry\)/);
assert.match(view, /I18n\.tr\("Search this type"\)/);
assert.match(view, /I18n\.tr\("No results"\)/);
assert.match(view, /TextInput \{/);

// ── P0 file operations and display parity ──
// Members reuse the desktop's shared file menu through a signal; the card
// owns an inline editor because the normal icon field is hidden.
assert.match(view, /property bool showExtensions: true/);
assert.match(view, /property var folderCustomizations/);
assert.match(view, /signal contextMenuRequested\(var entry, real x, real y\)/);
assert.match(view, /function displayName\(entry\)/);
assert.match(view, /function beginRename\(path\)/);
assert.match(view, /function commitRename\(entry, name\)/);
assert.match(view, /property var renameCallback: null/);
assert.match(view, /onDoubleTapped/);
assert.match(view, /contextMenuRequested\(tile\.entry/);
assert.match(view, /onActiveFocusChanged/);
assert.match(view, /Keys\.onReturnPressed/);
assert.match(view, /folderCustom: tile\.custom/);
assert.match(view, /tile\.custom\.color/);
// Member artwork and the grid metrics follow the desktop icon size setting.
assert.match(view, /property int iconSize: 56/);
assert.match(view, /readonly property int cellHeight/);
assert.match(view, /readonly property int columnWidth/);
assert.match(view, /readonly property int labelFontSize/);
assert.match(view, /Math\.floor\(width \/ root\.columnWidth\)/);
assert.match(view, /cellHeight: root\.cellHeight/);
assert.match(view, /size: root\.iconSize/);
assert.match(view, /pixelSize: root\.labelFontSize/);
// Single selection gives the same visible feedback as the normal icon field.
assert.match(view, /property string selectedPath: ""/);
assert.match(view, /function isSelected\(path\)/);
assert.match(view, /function selectOnly\(path\)/);
assert.match(view, /root\.selectOnly\(tile\.path\)/);
assert.match(view, /root\.isSelected\(tile\.path\)/);
assert.match(view, /id: tileHover/);
assert.match(view, /tileHover\.hovered/);
assert.match(deskcenter,
    /iconSize: desktopFileGrid\.desktopLayout\.iconSize/);
assert.match(deskcenter, /property var groupsContentItem/);
assert.match(deskcenter, /function beginGroupsRename\(entry\)/);
assert.match(deskcenter, /root\.beginGroupsRename\(entry\)/);
assert.match(deskcenter, /onContextMenuRequested: function\(entry, x, y\)/);
assert.match(deskcenter, /desktopFileGrid\.showMenu\(entry,/);
assert.match(deskcenter,
    /showExtensions: desktopFileGrid\.desktopLayout\.showExtensions/);
assert.match(deskcenter,
    /folderCustomizations: desktopFileGrid\._folderCustomCache/);
assert.match(deskcenter, /renameCallback: function\(entry, name\)/);
assert.match(memberIcon, /property var folderCustom: null/);
assert.match(memberIcon, /folderCustomized/);
assert.match(memberIcon, /DesktopFolderIcon \{/);
assert.ok(view.includes('id: searchField'), 'search field must exist');
assert.ok(!view.includes('LiquidTextField'),
    'the search bubble uses the widget palette, not a second liquid control');
assert.ok(!view.includes('searchType'),
    'type switching belongs to the left tabs, not the search bubble');
const closeStart = view.indexOf('function closeSearch()');
const closeEnd = view.indexOf('function toggleSearch()');
assert.ok(closeStart >= 0 && closeEnd > closeStart,
    'closeSearch moved; update this test');
const closeBody = view.slice(closeStart, closeEnd);
assert.ok(!closeBody.includes('searchField.text = ""'),
    'closing the bubble must not clear the visible query');
assert.ok(!closeBody.includes('searchQuery = ""'),
    'closing the bubble must not clear the active filter');
assert.match(view, /onEditingChanged/);
assert.match(deskwidget, /property bool allowColorArtwork: true/);

console.log('DESKTOP_GROUPS_PASS');
