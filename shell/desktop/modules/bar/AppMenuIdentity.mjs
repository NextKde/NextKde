// dbusmenu IDs may all change on rebuild. Labels are usable only when
// unambiguous in both snapshots; positions and recycled IDs are not identity.
export function resolve(previous, index, fresh) {
    const selected = previous[index];
    if (!selected || !selected.label) return -1;
    const matches = item => item.label === selected.label
        && Boolean(item.hasChildren) === Boolean(selected.hasChildren);
    if (previous.filter(matches).length !== 1) return -1;
    const candidates = fresh.map((item, i) => matches(item) ? i : -1).filter(i => i >= 0);
    return candidates.length === 1 ? candidates[0] : -1;
}
