#include <mimalloc.h>
#include <QCoreApplication>
#include <QImage>
#include <QByteArray>
#include <cstdio>
#include <cstdlib>
extern "C" __declspec(dllimport) void* dll_allocate();
extern "C" __declspec(dllimport) void dll_release(void*);
int main(int argc,char**argv){
  std::printf("mi_version=%d\n",mi_version());
  QCoreApplication app(argc,argv);
  void* a=std::malloc(1048576); auto* b=new char[1048576];
  QImage image(1024,1024,QImage::Format_ARGB32); image.fill(0xff124456);
  QByteArray bytes(1048576,'x');void* c=dll_allocate();void* d=mi_malloc(1048576);
  std::printf("malloc=%d new=%d QImage=%d QByteArray=%d external_DLL=%d explicit_mi_malloc=%d\n",
    mi_is_in_heap_region(a),mi_is_in_heap_region(b),mi_is_in_heap_region(image.constBits()),
    mi_is_in_heap_region(bytes.constData()),mi_is_in_heap_region(c),mi_is_in_heap_region(d));
  dll_release(a);std::free(c);delete[]b;mi_free(d);
}
