"""Desktop-side byte identity check; no authentication or shell execution."""
import hashlib
import base64
import json
import os
import stat
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlparse


def image_bytes(source, digest):
    if not re.fullmatch(r"[0-9a-f]{64}", digest): return None
    url = urlparse(source)
    if url.scheme not in ("", "file") or url.netloc: return None
    path = Path(unquote(url.path))
    if not path.is_absolute(): return None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        try:
            metadata = os.fstat(fd)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 32 * 1024 * 1024: return None
            with os.fdopen(fd, "rb", closefd=False) as stream:
                data = stream.read(32 * 1024 * 1024 + 1)
                if len(data) > 32 * 1024 * 1024: return None
                if hashlib.sha256(data).hexdigest() == digest: return data
                # T03 strips metadata/re-encodes PNG. Compare the same canonical
                # bytes, not the private JPEG/PNG encoding before publication.
                from resources import image_copy
                try: canonical, _ = image_copy(data)
                except (ValueError, OSError): return None
                return canonical if hashlib.sha256(canonical).hexdigest() == digest else None
        finally:
            os.close(fd)
    except OSError:
        return None


def match(source, digest):
    return image_bytes(source, digest) is not None


def published_bytes(digest, version, fit, root=None, owner=0):
    """Resolve only the current account's consented public image, never a QML path."""
    from handoff import PUBLIC_ROOT
    from wallpaper import Reader
    try:
        current = Reader(PUBLIC_ROOT if root is None else root, owner).consume(os.geteuid())
        if current:
            manifest, images = current
            data = images['wallpaper']
            if (manifest['version'] == version and manifest['fit'] == fit
                    and hashlib.sha256(data).hexdigest() == digest):
                return data
    except (OSError, ValueError):
        pass
    return None


if __name__ == "__main__":
    if len(sys.argv) not in (3, 5): sys.exit(2)
    source, digest = sys.argv[1:3]
    # Production uses the same revocable publication as Cover for every mode.
    # The two-argument identity utility remains available for isolated checks.
    data = published_bytes(digest, *sys.argv[3:]) if len(sys.argv) == 5 else image_bytes(source, digest)
    print(json.dumps(dict(source=source, hash=digest, match=data is not None, image="data:image/png;base64," + base64.b64encode(data).decode() if data is not None else "")))
