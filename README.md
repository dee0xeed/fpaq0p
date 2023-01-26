# fpaq0p
An implementation of [fpaq0p](http://nishi.dreamhosters.com/u/fpaq0p.cpp) entropy encoder in Zig.

# links
[PAQ](http://mattmahoney.net/dc/)

# fpaqi

Same encoder/decoder, but with different model.
See [here](https://encode.su/threads/4008-A-model-for-fpaq0p-like-compressor)

```
                        gzip  fpaq0p   fpaqi
 152089 alice29.txt    54435   87967   76636
 125179 asyoulik.txt   48951   75894   63217
  24603 cp.html         7999   16335   14268
  11150 fields.c        3143    6880    5769
   3721 grammar.lsp     1246    2235    2022
1029744 kennedy.xls   206779  403932  348806
 426754 lcet10.txt    144885  245895  214446
 481861 plrabn12.txt  195208  279789  235691
 513216 ptt5           56443   67909   61034
  38240 sum            12924   20754   19180
   4227 xargs.1         1756    2675    2567
```
