// History belongs to the open panel, and only completed service samples enter it.
export function empty(device = "") {
    return { device, download: [], upload: [] };
}

export function append(history, device, download, upload) {
    if (!device || !Number.isFinite(download) || !Number.isFinite(upload))
        return history;
    const current = history.device === device ? history : empty(device);
    // A full flat window need not repaint either chart on every idle sample.
    if (current.download.length === 60 && current.upload.length === 60
        && current.download.every(value => value === Math.max(0, download))
        && current.upload.every(value => value === Math.max(0, upload))) return current;
    return {
        device,
        download: current.download.concat([Math.max(0, download)]).slice(-60),
        upload: current.upload.concat([Math.max(0, upload)]).slice(-60),
    };
}
