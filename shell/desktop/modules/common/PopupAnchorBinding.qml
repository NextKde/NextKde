import QtQml
import QtQuick

// Quickshell 0.3.0 dereferences PopupAnchor::mItem when setItem(nullptr)
// follows a valid item. Retain the last anchor while hidden/unavailable;
// PopupAnchor's destroyed connection clears it when the item is destroyed.
QtObject {
    id: root
    required property var popupAnchor
    required property Item sourceItem
    // A Binding with separate value/when expressions can still write null
    // before its when condition updates. Only publish valid items explicitly.
    function synchronize() {
        if (root.popupAnchor && root.sourceItem)
            root.popupAnchor.item = root.sourceItem;
    }
    onSourceItemChanged: synchronize()
    onPopupAnchorChanged: synchronize()
    Component.onCompleted: synchronize()
}
