# compilation
Compile all programs with `-O ReleaseFast`, for example

```
$ /opt/zig-0.10.1/zig build-exe bswi12.zig -fsingle-threaded -O ReleaseFast
```

See also [here](https://ziggit.dev/t/strange-program-performance-dependence/525)

# fpaq0p
An implementation of [fpaq0p](http://nishi.dreamhosters.com/u/fpaq0p.cpp) entropy encoder in Zig.

## performance

### original c++ version (with -O3 g++ option)
$ time ./fpaq0p c ~/CC/enwik8 zz
enwik8 (100000000 bytes) -> zz (61457810 bytes) in 10.98 s.

real    0m11,093s
user    0m10,831s
sys 0m0,172s

### zig

$ time ./fpaq0p c ~/CC/enwik8 zz
enwik8 (100000000 bytes) -> zz (61457810 bytes) in 8890 msec

real    0m8,893s
user    0m8,753s
sys 0m0,136s

## links
[PAQ](http://mattmahoney.net/dc/)

# bswi*

## Encoder/Decoder

Borrowed from `fpaq0p`, but with some modifications:

* uses probability of zero instead of one
* and left (lower) interval corresponds to probabilty of zero
* bytes are processed from LSB to MSB
* no extra bits between bytes (original file size is stored in a compressed file)

## Probability model

In brief: Bit Sliding Window + posItion of a bit in a byte, hence the name.
See [here](https://encode.su/threads/4008-A-model-for-fpaq0p-like-compressor) for a discussion.

### calgary-corpus

```
                fpaq0p bswi08 bswi12 bswi16
111261  bib      73186  58206  56855  50838
768771  book1   442501 398301 361306 345004
610856  book2   360903 325904 298452 278986
102400  geo      71658  59866  68662  61223
377109  news    238373 215909 210622 192843
 21504  obj1     14288  12984  14934  13041
246814  obj2    179311 137710 141174 115730
 53161  paper1   32522  29133  30562  26521
 82199  paper2   47961  43383  42469  38348
 46526  paper3   27510  25184  25987  23070
 13286  paper4    7882   7374   8912   7463
 11954  paper5    7383   6871   8381   6997
 38105  paper6   22962  20813  22804  19504
513216  pic      67909  61034  63557  59489
 39611  progc    25273  21560  23884  20164
 71646  progl    40760  32855  33611  29016
 49379  progp    29410  23698  25448  21271
 93695  trans    60728  47709  47821  40308
```
### cunterbury-corpus
```
                       gzip fpaq0p bswi04 bswi08 bswi12 bswi16
 152089 alice29.txt   54435  87967  94473  76636  66242  61882
 125179 asyoulik.txt  48951  75894  81465  63217  55347  52835
  24603 cp.html        7999  16335  16994  14268  12739  12575
  11150 fields.c       3143   6880   7203   5769   5740   6058
   3721 grammar.lsp    1246   2235   2340   2022   2203   2374
1029744 kennedy.xls  206779 403932 410035 348806 271180 175144 (!)
 426754 lcet10.txt   144885 245895 263807 214446 185379 168142
 481861 plrabn12.txt 195208 279789 301601 235691 205080 190183
 513216 ptt5          56443  67909  64694  61034  59489  60114
  38240 sum           12924  20754  21322  19180  19218  20735
   4227 xargs.1        1756   2675   2821   2567   2814   3070
```
## mixing bswi08, bswi12 and bswi16

### calgary-corpus

```
   bib  40292
 book1 300266
 book2 241826
   geo  56726
  news 167999
  obj1  10881
  obj2 104838
paper1  21463
paper2  31914
paper3  19145
paper4   5702
paper5   5282
paper6  15445
   pic  53493
 progc  15895
 progl  23609
 progp  16103
 trans  31604
```

### cunterbury-corpus

```
                       naive logist
 152089 alice29.txt    63430  55862
 125179 asyoulik.txt   53460  46260
  24603 cp.html        12283   9244
  11150 fields.c        5560   3818
   3721 grammar.lsp     2101   1390
1029744 kennedy.xls   230530 259098 (?)
 426754 lcet10.txt    175868 159694
 481861 plrabn12.txt  197605 179807
 513216 ptt5           56343  53493
  38240 sum            18637  15563
   4227 xargs.1         2725   1851
```

## links
[BitCompressor](https://github.com/GotthardtZ/BitCompressor)  
[gallop](https://github.com/mitiko/gallop)  
[fpaq0 in Rust](https://github.com/aufdj/fpaq0-rs/blob/main/README.md)  
