#include <stdlib.h>
__declspec(dllexport) void* dll_allocate(){return malloc(1048576);}
__declspec(dllexport) void dll_release(void* p){free(p);}
