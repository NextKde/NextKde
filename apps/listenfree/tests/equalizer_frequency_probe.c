#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "iir.h"
int main(void) {
 const unsigned rates[]={22050,32000,44100,48000,88200,96000,192000};
 const double freqs[]={31,62,125,250,500,1000,2000,4000,8000,16000};
 double maxerr=0; int fail=0, count=0;
 eq_set_option(EQ_ISO_BANDS,1);eq_set_option(EQ_CLIP,1);eq_set_option(EQ_TWO_PASSES,0);
 for(unsigned r=0;r<sizeof(rates)/sizeof(rates[0]);++r) {
  unsigned rate=rates[r];float* pcm=malloc(rate*2*sizeof(float));eq_init_iir(rate,10);
  for(int b=0;b<10;++b) {if(freqs[b]>=rate*.5)continue;
   for(int mode=-1;mode<=1;++mode) {
    const double db=mode*6.;eq_clean_history();
    for(int c=0;c<2;++c){eq_set_preamp(c,4);for(int band=0;band<10;++band)eq_set_gain(band,c,band==b?(pow(10,db/20)-1)*.25:0);}
    double before=0,after=0;
    for(unsigned i=0;i<rate;++i){pcm[i*2]=pcm[i*2+1]=.02*sin(2*3.141592653589793*freqs[b]*i/rate);if(i>=rate/2)before+=pcm[i*2]*pcm[i*2];}
    eq_iir(pcm,rate*2,2);
    for(unsigned i=rate/2;i<rate;++i)after+=pcm[i*2]*pcm[i*2];
    double actual=10*log10(after/before),err=fabs(actual-db);if(err>maxerr)maxerr=err;
    ++count;if(!isfinite(actual)||err>.3){printf("FAIL %u Hz / band %.0f Hz / %.1f dB => %.5f dB\n",rate,freqs[b],db,actual);++fail;}
   }
  }
  free(pcm);
 }
 printf("%d gain cases, %d failed, max absolute error %.6f dB\n",count,fail,maxerr);return fail?1:0;
}
