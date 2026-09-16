#include "WavNormalization.hpp"
int main(int argc,char** argv){if(argc!=2)return 2;return normalizeWAV(argv[1])==noErr ? 0:1;}
