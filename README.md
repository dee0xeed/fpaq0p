# compilation
Compile all programs with `-O ReleaseFast`, for example

```
$ /opt/zig-0.10.1/zig build-exe bswi12.zig -fsingle-threaded -O ReleaseFast
```

See also [here](https://ziggit.dev/t/strange-program-performance-dependence/525)

# fpaq0p
An implementation of [fpaq0p](http://nishi.dreamhosters.com/u/fpaq0p.cpp) entropy encoder in Zig.

# links
[PAQ](http://mattmahoney.net/dc/)

# bswi*

Same encoder/decoder, but with different model.
In brief: Bit Sliding Window + posItion of a bit in a byte, hense the name.
See [here](https://encode.su/threads/4008-A-model-for-fpaq0p-like-compressor) for a discussion.

```cunterbury-corpus

                        gzip fpaq0p bswi08 bswi12 bswi16
 152089 alice29.txt   54435  87967  76636  66242  61882
 125179 asyoulik.txt  48951  75894  63217  55347  52835
  24603 cp.html        7999  16335  14268  12739  12575
  11150 fields.c       3143   6880   5769   5740   6058
   3721 grammar.lsp    1246   2235   2022   2203   2374
1029744 kennedy.xls  206779 403932 348806 271180 175144
 426754 lcet10.txt   144885 245895 214446 185379 168142
 481861 plrabn12.txt 195208 279789 235691 205080 190183
 513216 ptt5          56443  67909  61034  59489  60114
  38240 sum           12924  20754  19180  19218  20735
   4227 xargs.1        1756   2675   2567   2814   3070
```
# mixing 

```cunterbury-corpus

                       naive logist
 152089 alice29.txt    63430  56777
 125179 asyoulik.txt   53460  47096
  24603 cp.html        12283   9471
  11150 fields.c        5560   4041
   3721 grammar.lsp     2101   1499
1029744 kennedy.xls   230530 260940
 426754 lcet10.txt    175868 161412
 481861 plrabn12.txt  197605 181023
 513216 ptt5           56343  54659
  38240 sum            18637  16218
   4227 xargs.1         2725   1942
```
