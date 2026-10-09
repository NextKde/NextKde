"""Read-only Windows resident-page and allocation classification; no working-set trim."""
import bisect, collections, ctypes, json, pathlib, sys, time
from ctypes import wintypes as w

k = ctypes.WinDLL('kernel32', use_last_error=True)
p = ctypes.WinDLL('psapi', use_last_error=True)
k.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
k.OpenProcess.restype = w.HANDLE
k.CloseHandle.argtypes = [w.HANDLE]
p.QueryWorkingSet.argtypes = [w.HANDLE, ctypes.c_void_p, w.DWORD]
p.GetMappedFileNameW.argtypes = [w.HANDLE, ctypes.c_void_p, w.LPWSTR, w.DWORD]

class Region(ctypes.Structure):
    _fields_ = [('base', ctypes.c_void_p), ('allocation', ctypes.c_void_p),
                ('allocationProtect', w.DWORD), ('size', ctypes.c_size_t),
                ('state', w.DWORD), ('protect', w.DWORD), ('kind', w.DWORD)]

k.VirtualQueryEx.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.POINTER(Region), ctypes.c_size_t]
k.VirtualQueryEx.restype = ctypes.c_size_t

def resident_pages(handle):
    size = 1024 * 1024
    while size <= 64 * 1024 * 1024:
        data = ctypes.create_string_buffer(size)
        if p.QueryWorkingSet(handle, data, size):
            count = ctypes.c_size_t.from_buffer(data).value
            return (ctypes.c_size_t * count).from_buffer(data, ctypes.sizeof(ctypes.c_size_t))
        error = ctypes.get_last_error()
        if error != 24: raise ctypes.WinError(error)
        size *= 2
    raise RuntimeError('Working-set snapshot exceeds diagnostic bound')

def footprint(pid, allocations=False):
    handle = k.OpenProcess(0x410, False, pid)
    if not handle: raise ctypes.WinError(ctypes.get_last_error())
    started = time.monotonic()
    try:
        pages = resident_pages(handle)
        private = sum(not (flags & 0x100) for flags in pages)
        unique = sum(not (flags & 0x100) or ((flags >> 5) & 7) <= 1 for flags in pages)
        result = dict(pid=pid, pwsMiB=private / 256, ussMiB=unique / 256, wsMiB=len(pages) / 256)
        if allocations:
            regions, bases, grouped = [], [], collections.defaultdict(lambda: dict(commitMiB=0, pwsMiB=0, ussMiB=0, wsMiB=0))
            address = 0
            while True:
                region = Region()
                if not k.VirtualQueryEx(handle, address, ctypes.byref(region), ctypes.sizeof(region)): break
                base, end = region.base or 0, (region.base or 0) + region.size
                if end <= address: break
                address = end
                if region.state != 0x1000: continue
                kind = {0x20000:'private',0x40000:'mapped',0x1000000:'image'}.get(region.kind,hex(region.kind))
                name = kind
                if kind != 'private':
                    path = ctypes.create_unicode_buffer(32768)
                    if p.GetMappedFileNameW(handle, base, path, len(path)): name += ':' + pathlib.PureWindowsPath(path.value).name
                else: name += ':' + hex(region.allocation or base)
                bases.append(base); regions.append((end, name))
                grouped[name]['commitMiB'] += region.size / 1048576
            for flags in pages:
                address = (flags >> 12) * 4096
                index = bisect.bisect_right(bases, address) - 1
                if index < 0 or address >= regions[index][0]: continue
                values = grouped[regions[index][1]]
                values['wsMiB'] += 1 / 256
                if not (flags & 0x100): values['pwsMiB'] += 1 / 256
                if not (flags & 0x100) or ((flags >> 5) & 7) <= 1: values['ussMiB'] += 1 / 256
            result['allocations'] = sorted([dict(name=name, **values) for name, values in grouped.items()], key=lambda r:r['ussMiB'], reverse=True)
            totals = collections.defaultdict(lambda: dict(commitMiB=0,pwsMiB=0,ussMiB=0,wsMiB=0))
            for row in result['allocations']:
                for key in totals[row['name'].split(':',1)[0]]: totals[row['name'].split(':',1)[0]][key] += row[key]
            result['byType'] = dict(totals)
        result['queryMs'] = round((time.monotonic() - started) * 1000, 2)
        return result
    finally: k.CloseHandle(handle)

if __name__ == '__main__':
    result = footprint(int(sys.argv[1]), allocations=True)
    if len(sys.argv) > 2: pathlib.Path(sys.argv[2]).write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({key:value for key,value in result.items() if key != 'allocations'}, indent=2))
    print(json.dumps(result['allocations'][:15], indent=2))
