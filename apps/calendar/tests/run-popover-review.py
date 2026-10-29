#!/usr/bin/env python3
"""Explicit graphical review, with an isolated D-Bus session and temporary PIM data.
Run only on an authorized desktop/VM, after building kos-calendar and kos-pim-service.
"""
from pathlib import Path
import os
import base64
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[3]
build = Path(sys.argv[-1]).resolve() if len(sys.argv) > 1 else repo / '.build/apps-release'
if '--session' not in sys.argv:
    raise SystemExit(subprocess.call(['dbus-run-session', '--', sys.executable, __file__, '--session', str(build)]))
with tempfile.TemporaryDirectory(prefix='calendar-popover-review-') as folder:
    work = Path(folder)
    (work / "sample.png").write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAEp0lEQVR4nBXOsQqFhgEAwHxThw4ODg4ODg4ODg4OUiwIkWJBiAQDQqRYECrBgBApFoRKMBAaCAQC/bL23nD7ffGHP/3nf38kICQiJiElI6egpKKmoaWjZ2BkYmZhZWPn4OTi5uHliz/8WYCAkIiYhJSMnIKSipqGlo6egZGJmYWVjZ2Dk4ubh/fPn0AjQEBIRExCSkZOQUlFTUNLR8/AyMTMwsrGzsHJxc3D23wCXwoQEBIRk5CSkVNQUlHT0NLRMzAyMbOwsrFzcHJx8/B++Qn8RYCAkIiYhJSMnIKSipqGlo6egZGJmYWVjZ2Dk4ubh/cvn8BfBQgIiYhJSMnIKSipqGlo6egZGJmYWVjZ2Dk4ubh5eP/6CfQCBIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3Dy8/SfwlQABIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3D+9Xn8DXAgSERMQkpGTkFJRU1DS0dPQMjEzMLKxs7BycXNw8vF9/At8IEBASEZOQkpFTUFJR09DS0TMwMjGzsLKxc3BycfPwfvMJTAIEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcPLzTJ/CtAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP77efwN8ECAiJiElIycgpKKmoaWjp6BkYmZhZWNnYOTi5uHl4//YJ/F2AgJCImISUjJyCkoqahpaOnoGRiZmFlY2dg5OLm4f375/AKkBASERMQkpGTkFJRU1DS0fPwMjEzMLKxs7BycXNw7t+Av8QICAkIiYhJSOnoKSipqGlo2dgZGJmYWVj5+Dk4ubh/ccn8J0AASERMQkpGTkFJRU1DS0dPQMjEzMLKxs7BycXNw/vd5/A9wIEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcPLzffwKHAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP7/EJ/CBAQEhETEJKRk5BSUVNQ0tHz8DIxMzCysbOwcnFzcP7wyfwTwECQiJiElIycgpKKmoaWjp6BkYmZhZWNnYOTi5uHt5/fgL/EiAgJCImISUjp6CkoqahpaNnYGRiZmFlY+fg5OLm4f3XJ3ALEBASEZOQkpFTUFJR09DS0TMwMjGzsLKxc3BycfPw3p/AvwUICImISUjJyCkoqahpaOnoGRiZmFlY2dg5OLm4eXj//Qn8KEBASERMQkpGTkFJRU1DS0fPwMjEzMLKxs7BycXNw/vjJ/CTAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP70+fwM8CBIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3Dy8P38CvwgQEBIRk5CSkVNQUlHT0NLRMzAyMbOwsrFzcHJx8/D+8gn8KkBASERMQkpGTkFJRU1DS0fPwMjEzMLKxs7BycXNw/vrJ/CbAAEhETEJKRk5BSUVNQ0tHT0DIxMzCysbOwcnFzcP72+fwO8CBIRExCSkZOQUlFTUNLR09AyMTMwsrGzsHJxc3Dy8v38C/xUgICQiJiElI6egpKKmoaWjZ2BkYmZhZWPn4OTi5uHl/wM61pdGhb6uAAAAAElFTkSuQmCC"))
    qml = work / 'qml'
    qml.mkdir()
    for source in (repo / 'apps/calendar/qml').iterdir():
        if source.suffix in ('.qml', '.js'):
            shutil.copy2(source, qml / source.name)
    main = qml / 'Main.qml'
    source = main.read_text().replace('import QtQuick\n', 'import QtQuick\nimport QtTest\n', 1)
    fixture_name = os.environ.get('KOS_CALENDAR_REVIEW_FIXTURE', 'PopoverInteractions.qml.inc')
    fixture = Path(__file__).with_name(fixture_name).read_text()
    main.write_text(source.replace('    neutralTypography: true', fixture + '\n    neutralTypography: true', 1))
    env = dict(os.environ, KOS_PIM_STORAGE_DIR=str(work / 'data'), XDG_CONFIG_HOME=str(work / 'config'),
               QT_FORCE_STDERR_LOGGING='1', QT_QPA_PLATFORM='wayland', LANG='zh_CN.UTF-8', LANGUAGE='zh_CN:zh')
    service = subprocess.Popen([str(build / 'services/pim-service/kos-pim-service')], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        result = subprocess.run([str(build / 'apps/calendar/kos-calendar'), '--watch-qml', str(qml)],
                                env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=35)
        print(result.stdout)
        print("Calendar review exit:", result.returncode)
        if (result.returncode or (fixture_name == 'PopoverInteractions.qml.inc'
                and 'POPOVER_RANGE_TESTS_PASSED' not in result.stdout)
                or 'REMINDER_ORGANIZATION_TESTS_PASSED' not in result.stdout
                or 'FAIL!' in result.stdout):
            raise SystemExit('Popover interaction review failed')
    finally:
        service.terminate()
        service.wait(timeout=5)
