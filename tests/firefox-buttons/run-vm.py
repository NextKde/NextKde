#!/usr/bin/env python3
"""VM-only Firefox browser-chrome and nested KWin integration acceptance."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
import firefox_buttons as adapter


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path, required=True)
    parser.add_argument('--firefox', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--gnome-theme', type=Path)
    parser.add_argument('--session', action='store_true')
    args=parser.parse_args()
    out=args.output.resolve()
    if args.session:
        session(args,out); return
    out.mkdir(parents=True,exist_ok=False)
    plugin=out/'plugins/kwin/effects/plugins'; plugin.mkdir(parents=True)
    shutil.copy2(args.bridge,plugin/'kos_bridge.so')
    config=out/'config'; (config/'kos').mkdir(parents=True)
    (config/'gtk-3.0').mkdir()
    (config/'gtk-3.0/settings.ini').write_text('[Settings]\ngtk-decoration-layout=:minimize,maximize,close\n')
    (config/'kwinrc').write_text('[org.kde.kdecoration2]\nlibrary=org.kde.breeze\n[Plugins]\nkos_bridgeEnabled=true\n')
    (config/'kos/window-appearance.json').write_text('{"enabled":true,"version":2}')
    # Force overlay eligibility so the native-control exclusion is actually tested.
    (config/'kos/window-buttons.json').write_text(json.dumps({'default':{'drawOnDecoratedWindows':'always','background':'dark'}}))
    wrapper=out/'session.sh'
    wrapper.write_text('#!/bin/sh\nexec '+shlex.join([sys.executable,str(Path(__file__).resolve()),'--session','--bridge',str(args.bridge.resolve()),'--firefox',str(args.firefox.resolve()),'--output',str(out)] + (['--gnome-theme',str(args.gnome_theme.resolve())] if args.gnome_theme else []))+'\n')
    wrapper.chmod(0o700)
    env=dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(out/'data'), QT_PLUGIN_PATH=str(out/'plugins'))
    with (out/'kwin.log').open('w') as log, subprocess.Popen(['dbus-run-session','kwin_wayland','--wayland-display',os.environ.get('WAYLAND_DISPLAY','wayland-0'),
        '--socket',f'firefox-test-{os.getpid()}','--width','1100','--height','760','--no-lockscreen','--no-global-shortcuts','--no-kactivities','--exit-with-session',str(wrapper)],
        env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True) as proc:
        try: proc.wait(timeout=240)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid,signal.SIGTERM); proc.wait(timeout=10); raise
    assert (out/'passed').exists(), (out/'kwin.log').read_text()[-6000:]
    print('PASS:',out)


def session(args,out):
    from marionette_driver.marionette import Marionette
    profile=out/'profile'; profile.mkdir()
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
    prefs={'marionette.port':port,'browser.tabs.inTitlebar':1,'browser.shell.checkDefaultBrowser':False,
        'browser.startup.homepage':'about:blank','browser.startup.page':0,'browser.aboutwelcome.enabled':False,
        'browser.sessionstore.resume_from_crash':False,'browser.tabs.warnOnClose':False,
        'browser.startup.homepage_override.mstone':'ignore','datareporting.policy.dataSubmissionEnabled':False}
    (profile/'user.js').write_text(''.join(f'user_pref({json.dumps(k)}, {json.dumps(v)});\n' for k,v in prefs.items()))
    if args.gnome_theme:
        (profile/'chrome').mkdir()
        (profile/'chrome/firefox-gnome-theme').symlink_to(args.gnome_theme)
        (profile/'chrome/userChrome.css').write_text('@import "firefox-gnome-theme/userChrome.css";\n')
        prefs_file=profile/'theme-user.js'
        prefs_file.write_text((profile/'user.js').read_text() + (args.gnome_theme/'configuration/user.js').read_text())
        (profile/'user.js').unlink()
        (profile/'user.js').symlink_to(prefs_file)
    config=out/'config'
    subprocess.run(['gsettings','set','org.gnome.desktop.wm.preferences','button-layout',':minimize,maximize,close'], check=True)
    adapter.install(config,[profile])
    def reconfigure():
        subprocess.run(['qdbus6','org.kde.KWin','/Effects','org.kde.kwin.Effects.reconfigureEffect','kos_bridge'],check=True)
    def diagnostics():
        return json.loads(subprocess.check_output(['qdbus6','org.kde.KWin','/Effects','org.kde.kwin.Effects.debug','kos_bridge','window-controls'],text=True))
    def wait(predicate):
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            result=predicate()
            if result: return result
            time.sleep(.15)
        raise AssertionError('Timed out waiting for Firefox state')
    reconfigure()
    evidence=[]
    for mode, theme, enabled in [('always','light',True),('hover','dark',True),('always','light',False)]:
        adapter.sync(config,enabled,mode)
        env=dict(os.environ, MOZ_ENABLE_WAYLAND='1', MOZ_GTK_TITLEBAR_DECORATION='client', GTK_THEME='Adwaita'+(':dark' if theme=='dark' else ''))
        with (out/f'firefox-{mode}-{theme}-{enabled}.log').open('w') as log, subprocess.Popen(
            [str(args.firefox),'--no-remote','--profile',str(profile),'--marionette','--remote-allow-system-access','about:blank'],
            env=env,stdout=log,stderr=subprocess.STDOUT) as browser:
            m=Marionette(host='127.0.0.1',port=port,socket_timeout=15,startup_timeout=30)
            try:
                m.start_session(); m.set_context('chrome')
                theme_id='firefox-compact-dark@mozilla.org' if theme=='dark' else 'firefox-compact-light@mozilla.org'
                result=m.execute_async_script('''const done=arguments[arguments.length-1];
                    const {AddonManager}=ChromeUtils.importESModule('resource://gre/modules/AddonManager.sys.mjs');
                    AddonManager.getAddonByID(arguments[0]).then(addon=>addon.enable()).then(()=>done(true),e=>done(String(e)));''',[theme_id])
                assert result is True, result

                wait(lambda: m.execute_script('return document.querySelectorAll(".titlebar-close").length > 0;'))
                m.execute_script('window.restore(); window.resizeTo(900, 600);')
                wait(lambda: m.execute_script('return window.windowState === window.STATE_NORMAL;'))
                def inspect():
                    return m.execute_script('''return Array.from(document.querySelectorAll('.titlebar-button')).filter(b=>b.getBoundingClientRect().width>0 && b.contains(document.elementFromPoint(b.getBoundingClientRect().x+b.getBoundingClientRect().width/2,b.getBoundingClientRect().y+b.getBoundingClientRect().height/2)) && ['titlebar-close','titlebar-max','titlebar-restore','titlebar-min'].some(c=>b.classList.contains(c))).map(b=>{const i=b.querySelector('.toolbarbutton-icon'),s=getComputedStyle(i),r=i.getBoundingClientRect(); return {name:b.className,color:s.backgroundColor,image:s.backgroundImage,width:r.width,height:r.height,radius:s.borderRadius};});''')
                wait(lambda: len(inspect())==3)
                windows=wait(lambda:[w for w in diagnostics()['windows'] if 'firefox' in w['windowClass'].lower()])
                assert all(w['nativeControls'] and not w['painted'] and not w['sampling'] and not w['decorated'] for w in windows),windows
                m.actions.sequence('pointer','test-mouse',{'pointerType':'mouse'}).pointer_move(350,300).perform()
                styles=inspect()
                if enabled:
                    assert all(x['width']==14 and x['height']==14 and x['radius']=='50%' for x in styles),styles
                    assert set(x['color'] for x in styles)=={'rgb(255, 95, 87)','rgb(254, 188, 46)','rgb(40, 200, 64)'},styles
                    if mode=='always': assert all('data:image/svg+xml' in x['image'] for x in styles),styles
                    else:
                        assert all(x['image']=='none' for x in styles),styles
                        close=m.execute_script("return Array.from(document.querySelectorAll('.titlebar-close')).find(b=>b.getBoundingClientRect().width>0 && b.contains(document.elementFromPoint(b.getBoundingClientRect().x+b.getBoundingClientRect().width/2,b.getBoundingClientRect().y+b.getBoundingClientRect().height/2)));")
                        m.actions.sequence('pointer','test-mouse',{'pointerType':'mouse'}).pointer_move(0,0,origin=close).perform()
                        wait(lambda: all('data:image/svg+xml' in x['image'] for x in inspect()))

                else:
                    assert not any('data:image/svg+xml' in x['image'] for x in styles),styles
                if theme == 'dark':
                    wait(lambda:m.execute_script("return matchMedia('(prefers-color-scheme: dark)').matches;"))
                (out/f'{mode}-{theme}-{enabled}.png').write_bytes(m.screenshot(format='binary',full=False))
                evidence.append({'version':m.session.get('browserVersion'),'mode':mode,'theme':theme,'enabled':enabled,'styles':styles,'windows':windows})
                if mode=='always' and enabled:
                    # Positive control: without qualification, this exact window
                    # receives the legacy panel. Reapply and prove it disappears.
                    adapter.qualify(config, remove=True); reconfigure()
                    wait(lambda:any(w['painted'] for w in diagnostics()['windows'] if 'firefox' in w['windowClass'].lower()))
                    # Unrelated config writes must not erase a legacy panel's
                    # accepted tint while the cooperative watcher refreshes.
                    rules_path=config/'kos/window-buttons.json'
                    rules=json.loads(rules_path.read_text())
                    rules['default']['background']='auto'
                    rules_path.write_text(json.dumps(rules)); reconfigure()
                    wait(lambda:any(w['painted'] for w in diagnostics()['windows'] if 'firefox' in w['windowClass'].lower()))
                    churn=[]
                    for index in range(30):
                        unrelated=config/f'unrelated-{index}.tmp'
                        unrelated.write_text('unrelated application settings')
                        time.sleep(.01)
                        states=[w for w in diagnostics()['windows'] if 'firefox' in w['windowClass'].lower()]
                        churn.append(states)
                        unrelated.unlink()
                    (out/'config-churn.json').write_text(json.dumps(churn,indent=2))
                    assert all(states and all(w['painted'] for w in states) for states in churn), 'Legacy panel disappeared during unrelated config changes'
                    adapter.qualify(config); reconfigure()
                    wait(lambda:all(not w['painted'] and w['nativeControls'] for w in diagnostics()['windows'] if 'firefox' in w['windowClass'].lower()))
                    def button(selector):
                        return m.execute_script("return Array.from(document.querySelectorAll(arguments[0])).find(b=>b.getBoundingClientRect().width>0 && b.contains(document.elementFromPoint(b.getBoundingClientRect().x+b.getBoundingClientRect().width/2,b.getBoundingClientRect().y+b.getBoundingClientRect().height/2)));",[selector])
                    button('.titlebar-max, .titlebar-restore').click()
                    wait(lambda:m.execute_script('return window.windowState === window.STATE_MAXIMIZED;'))
                    button('.titlebar-max, .titlebar-restore').click()
                    wait(lambda:m.execute_script('return window.windowState === window.STATE_NORMAL;'))
                    button('.titlebar-min').click()
                    wait(lambda:any(w['minimized'] for w in diagnostics()['windows'] if 'firefox' in w['windowClass'].lower()))
                    m.execute_script('window.restore(); window.focus();')
                    wait(lambda:not any(w['minimized'] for w in diagnostics()['windows'] if 'firefox' in w['windowClass'].lower()))
                    # Native close action ends this isolated test browser only.
                    try: button('.titlebar-close').click()
                    except Exception:
                        if browser.poll() is None: raise
                    browser.wait(timeout=10)
            finally:
                try: m.delete_session()
                except Exception: pass
                if browser.poll() is None:
                    browser.terminate(); browser.wait(timeout=10)
    (out/'evidence.json').write_text(json.dumps(evidence,indent=2))
    (out/'passed').write_text('Firefox own chrome styles/actions and no KWin overlay passed.\n')

if __name__=='__main__': main()
