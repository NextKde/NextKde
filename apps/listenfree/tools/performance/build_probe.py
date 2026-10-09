"""Link an isolated diagnostic entry against existing Release application objects.
Never writes src/, QML, CMake files, normal objects or the portable package.
"""
import argparse,ctypes,json,os,pathlib,re,shutil,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[2]
probe=root/'build/performance-optimization/probe';probe.mkdir(parents=True,exist_ok=True)
shutil.copy2(pathlib.Path(__file__).with_name('immersive_memory_probe.h'),probe/'immersive_memory_probe.h')
parser=argparse.ArgumentParser();parser.add_argument('--runtime',type=pathlib.Path,default=probe.parent/'runtime');parser.add_argument('--runtime-source',type=pathlib.Path,default=root/'dist/ListenFree-Portable');parser.add_argument('--build-dir',type=pathlib.Path,default=root/'build/performance-verify');parser.add_argument('--link-only',action='store_true');parser.add_argument('--heap-manifest',type=pathlib.Path);parser.add_argument('--legacy-heap',action='store_true');options=parser.parse_args()
build_dir=options.build_dir.resolve()
runtime=options.runtime.resolve();runtime.mkdir(parents=True,exist_ok=True)
shutil.copytree(options.runtime_source,runtime,dirs_exist_ok=True,ignore=shutil.ignore_patterns('data','listenfree.exe'))
for name in ['libqmmp.dll','libqmmpui.dll']:
    if (build_dir/name).exists():shutil.copy2(build_dir/name,runtime/name)
main=(root/'src/app/main.cpp').read_text(encoding='utf-8-sig')
# Count real decoder requests only in the isolated benchmark entry.
provider=(root/'src/qmlbridge/cover_image_provider.h').read_text(encoding='utf-8-sig')
provider=provider.replace('QImage requestImage(const QString& id, QSize* size, const QSize& requested) override {',
    'QImage requestImage(const QString& id, QSize* size, const QSize& requested) override {\n        static const bool countRequests=qEnvironmentVariableIsSet("LISTENFREE_COUNT_COVERS");\n        if(countRequests) qInfo().noquote() << "PERF_COVER_REQUEST" << requested << id;')
(probe/'cover_image_provider_probe.h').write_text(provider,encoding='utf-8')
main=main.replace('"qmlbridge/cover_image_provider.h"','"cover_image_provider_probe.h"')
main=re.sub(r'^#include "../../tools/[^\n]+\n','',main,flags=re.M)
main=main.split('    const auto validationIndex =')[0]
main=main.replace('int main(int argc, char* argv[]) {','#include "immersive_memory_probe.h"\nint main(int argc, char* argv[]) {')
main+='''
    std::unique_ptr<listenfree::qmlbridge::AccountService> auditAccounts;
    const int auditIndex=arguments.indexOf("--audit-config");
    if(auditIndex>=0 && auditIndex+1<arguments.size()) {
        QFile configFile(arguments[auditIndex+1]);
        if(configFile.open(QIODevice::ReadOnly)) {
            const QString profile=QJsonDocument::fromJson(configFile.readAll()).object().value("accountProfile").toString();
            if(!profile.isEmpty()) {
                // restore() validates existing Credential Manager data without rewriting it.
                auditAccounts=std::make_unique<listenfree::qmlbridge::AccountService>(profile);
                QObject::connect(auditAccounts.get(),&listenfree::qmlbridge::AccountService::accountsChanged,&immersive,[&] {
                    auto cookie=auditAccounts->cookieForRequest("bilibili");
                    app.setProperty("auditBiliAuthenticated",!cookie.isEmpty());
                    immersive.setBilibiliCookie(cookie);sourceController.bilibili().setCookie(cookie);cookie.fill(0);
                });
                auditAccounts->restore();
            }
        }
    }
    runImmersiveMemoryProbe(app,mainWindow,mainShell,controller,settingsController,immersive,sourceController,playlistController,arguments);
    return app.exec();
}
'''
(probe/'main.cpp').write_text(main,encoding='utf-8')
def split_command(value):
    count=ctypes.c_int();fn=ctypes.windll.shell32.CommandLineToArgvW
    fn.restype=ctypes.POINTER(ctypes.c_wchar_p);fn.argtypes=[ctypes.c_wchar_p,ctypes.POINTER(ctypes.c_int)]
    ptr=fn(value,ctypes.byref(count));args=[ptr[i] for i in range(count.value)]
    ctypes.windll.kernel32.LocalFree(ptr);return args
def commands(rule):
    result=subprocess.run(['F:/QT/Tools/Ninja/ninja.exe','-C',str(build_dir),'-t','compdb','-x',rule],capture_output=True,text=True,encoding='utf-8',check=True)
    return json.loads(result.stdout)
compile_entry=next(e for e in commands('CXX_COMPILER__listenfree_unscanned_Release') if e['file'].replace('\\','/').endswith('/src/app/main.cpp'))
compile_args=split_command(compile_entry['command'])
result=[];i=0
while i<len(compile_args):
    arg=compile_args[i]
    if arg in ['-MT','-MF','-o','-c']:
        if arg=='-o':result+=['-o',str(probe/'main.obj')]
        elif arg=='-c':result+=['-c',str(probe/'main.cpp')]
        i+=2;continue
    if arg!='-MD':result.append('-O1' if arg=='-O3' else arg)
    i+=1
result+=['-I'+str(root/'src/app'),'-I'+str(root/'src/qmlbridge'),'-I'+str(probe)]
for module in ['QtCore','QtGui','QtQml','QtQmlModels','QtQuick']:
    result+=['-IF:/QT/6.11.2/mingw_64/include/'+module+'/6.11.2','-IF:/QT/6.11.2/mingw_64/include/'+module+'/6.11.2/'+module]
env=dict(os.environ);env['PATH']='F:/QT/Tools/mingw1310_64/bin;F:/QT/6.11.2/mingw_64/bin;'+env['PATH']
with (probe/'build.log').open('w',encoding='utf-8') as log:
    if options.heap_manifest:
        resource=probe/'heap-manifest.rc';resource.write_text('1 24 "'+options.heap_manifest.resolve().as_posix()+'"\n',encoding='utf-8')
        subprocess.run(['F:/QT/Tools/mingw1310_64/bin/windres.exe','-i',str(resource),'-o',str(probe/'heap-manifest.obj'),'-O','coff'],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    if '--link-only' not in sys.argv:
        subprocess.run(result,cwd=build_dir,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    link=commands('CXX_EXECUTABLE_LINKER__listenfree_Release')[0]['command']
    link=split_command(link.split(' && ',1)[1].split(' && ',1)[0])
    link=[str(probe/'main.obj') if a.replace('\\','/')=='CMakeFiles/listenfree.dir/src/app/main.cpp.obj' else a for a in link]
    link[link.index('-o')+1]=str(runtime/'listenfree.exe')
    link=[('-Wl,--out-implib,'+str(probe/'diagnostic.dll.a')) if a.startswith('-Wl,--out-implib,') else a for a in link]
    if options.heap_manifest or options.legacy_heap:link=[a for a in link if not a.replace('\\','/').endswith('/src/app/segment_heap.rc.obj')]
    if options.heap_manifest:link.insert(1,str(probe/'heap-manifest.obj'))
    subprocess.run(link,cwd=build_dir,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
metadata={'sourceExecutable':str(build_dir/'listenfree.exe'),'sourceSize':(build_dir/'listenfree.exe').stat().st_size,
 'diagnostic':str(runtime/'listenfree.exe'),'diagnosticSize':(runtime/'listenfree.exe').stat().st_size,
 'basis':'Existing Release application/QML objects; separate instrumented entry; production source and executable untouched.'}
(probe/'build.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8');print(json.dumps(metadata),flush=True)
