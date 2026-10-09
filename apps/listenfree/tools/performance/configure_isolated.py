import pathlib,subprocess,os
root=pathlib.Path(__file__).resolve().parents[2]
selected={'CMAKE_BUILD_TYPE','CMAKE_CXX_COMPILER','CMAKE_MAKE_PROGRAM','CMAKE_PREFIX_PATH'}
lines=[]
for row in (root/'build/portable/CMakeCache.txt').read_text(encoding='utf-8').splitlines():
    if row.startswith('//') or ':' not in row or '=' not in row:continue
    key,rest=row.split(':',1);kind,value=rest.split('=',1)
    if key in selected or key.startswith('LISTENFREE_'):
        lines.append(f'set({key} [[{value.replace(chr(92),"/")}]] CACHE {"STRING" if kind=="UNINITIALIZED" else kind} "" FORCE)')
cache=root/'build/performance-optimization/probe/isolated-cache.cmake';cache.parent.mkdir(parents=True,exist_ok=True);cache.write_text('\n'.join(lines),encoding='utf-8')
env=dict(os.environ);env['PATH']='F:/QT/Tools/mingw1310_64/bin;F:/QT/6.11.2/mingw_64/bin;'+env['PATH']
subprocess.run(['F:/QT/Tools/CMake_64/bin/cmake.exe','-S',str(root),'-B',str(root/'build/performance-verify'),'-G','Ninja','-C',str(cache)],env=env,check=True)
