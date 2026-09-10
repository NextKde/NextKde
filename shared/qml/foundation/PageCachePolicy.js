.pragma library

function validIndex(index, pageCount) {
    return Number.isInteger(index) && index >= 0 && index < pageCount
}

function isPinned(index, pinnedIndexes, pageCount) {
    return validIndex(index, pageCount)
        && pinnedIndexes && pinnedIndexes.indexOf(index) >= 0
}

function trim(entries, currentIndex, pinnedIndexes, cacheLimit, pageCount) {
    const retained = ({})
    const keys = Object.keys(entries || ({}))
    for (let position = 0; position < keys.length; position++) {
        const key = keys[position]
        const index = Number(key)
        if (validIndex(index, pageCount))
            retained[String(index)] = entries[key]
    }

    let retainedMinimum = validIndex(currentIndex, pageCount) ? 1 : 0
    for (let index = 0; index < pageCount; index++) {
        if (isPinned(index, pinnedIndexes, pageCount)
                && index !== currentIndex)
            retainedMinimum++
    }
    const effectiveLimit = Math.max(retainedMinimum, cacheLimit, 1)

    while (Object.keys(retained).length > effectiveLimit) {
        let oldestKey = ""
        let oldestUse = Number.MAX_SAFE_INTEGER
        const retainedKeys = Object.keys(retained)
        for (let position = 0; position < retainedKeys.length; position++) {
            const key = retainedKeys[position]
            const index = Number(key)
            if (index === currentIndex
                    || isPinned(index, pinnedIndexes, pageCount))
                continue
            if (retained[key] < oldestUse) {
                oldestUse = retained[key]
                oldestKey = key
            }
        }
        if (oldestKey.length === 0)
            break
        delete retained[oldestKey]
    }
    return retained
}
