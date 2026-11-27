# Divergence labels: reservations and use

`docs/divergences.md` labels are stable ids: a retired label is never reused. **243 live, next label 251**
(also in `CLAUDE.md`). A milestone that expects divergences reserves a block of ten; a new divergence takes the
next sequential label or the next unused label of its milestone's block. Update this list and `CLAUDE.md`'s
"next label" in the commit that adds the row.

Moved verbatim from `CLAUDE.md` on 2026-11-18, one entry per item:

- 250 used by `SP-O` (an identifier on a `ScrollView` names a group node, not an `AXScrollArea`); the next label is 251 (251–254 were C21's block and are unused)
- 244 used by `OG-Q` (`backgroundProminence`: every selected row reads `.increased`, hierarchical styles do not adapt); the next label is 250 (245–248 are live, 249 is retired, 250–254 were C21's block and are unused)
- 243 used by `IV-S` (a write read only below a memo boundary rebuilds each plain ancestor once)
- 242 used by `MN-AP` (`Label` has no `labelStyle`), 1085 used by `OG-L` (the same-transaction reveal), 1086 used by `OG-M` (the ⌥ cascade over bindings), 1087 used by `OG-O` (the content list's flatten cache), 1088 used by `OG-P` (the splice animation is paint only and realised rows only) and 1089–1094 unused (1085–1094 reserved by OG)
- 241 used by `WB-C`, 232–234 and 237–240 used by `VT` (235 and 236 are the gesture rows), 230–231 used by `SYM-I`/`SYM-J`, 227–229 used by `SYM-C`/`SYM-H`, 226 used by `DSA-A`, 224 used by `CM-H`, 225 used, 91 and 92 retired by `CM-A` and `CM-B`, 109 retired by `TZ-B`, 217 used by `FC-G`, 218 by `LI-G`, 219 by `VF-D`, 220 by `VF-E`, 221 (retired by `GF-A`) and 222 by `GO-H`, 223 by `GF-H`, 1066 retired by `GF-A`
- 1125–1134 reserved by TXS: 1125 (AccessKit publishes no selection), 1126 (a string change drops the selection), 1127 (a client cannot set it) and 1128 (the right-click menu) used by record 399, 1129–1134 unused; the block is TXS's own because 245–248 were already live when the milestone was planned ("from 244"), and 244 stays the next label
- 1115–1124 reserved by SCF: 1115–1117 used and 1118–1124 unused
- 1105–1114 reserved by TBL: 1105 (uniform rows, `TBL-F`), 1106 (the default string comparator off Darwin, `TBL-X`; the shrink use the plan reserved it for is unneeded, the probe having shown SwiftUI does not shrink, `W3`) and 1110 (the type shape, `TBL-B`) used by record 389; 1108 (RTL) unused, MetalUI mirroring as SwiftUI does (`L1`); 1109 (no type-select, `TBL-O`) used by record 390 (probe arm `K6`); 1111 (resize compensation, `TBL-R`) used by record 391 (the probe `R2` confirmed it); 1107 (the AppKit shape of a table's accessibility, `TBL-T`, `TBL-AB`) used by record 392; 1112–1114 unused
- 1095–1104 reserved by TRM: unused
- 1085–1094 reserved by OG: unused
- 1075–1084 reserved by AD: 1075, 1076, 1078 and 1079 used and 1077 and 1080–1084 unused
- 1065–1074 reserved by PJ: 1065–1069 used (1066 retired) and 1070–1074 unused
- 1055–1064 reserved by DE: 1055, 1056 used and 1057–1064 unused
- 1045–1054 reserved by LD: 1045 used, 1046–1054 unused
- 1035–1044 reserved by AE: 1035, 1036 used and 1037–1044 unused
- 1025–1034 reserved by LB: 1025 and 1026 used, 1027–1034 unused
- 1015–1024 reserved by PH: unused
- 995–1004 reserved by TM: none used
- 985–994 reserved by GL: unused
- 975–984 reserved by SS: 975–977 used and 978–984 unused
- 945–947 used and 948–954 unused by PG
- 915–916 used and 917–924 unused by SP
- 925 used and 926–934 unused by GE
- 935 and 936 used and 937–944 unused by SV-AO (936 by `SV-AQ`: `fileDialogDefaultDirectory` on SDL)
- 895–898 used and 899–904 unused by MG
- 885–894 reserved by BY: 885 (retired) and 886 used, 887–894 unused
- 207 never published and unused
- 209 used by `SV-AM`
- 210 retired by `ER-A`, 211 and 212 used by `ER-C`
- 120 and 255 retired and 745–754 unused by LH
- 735–737 used and 738–744 unused by BG
- 705–714 unused by DT
- 625–634 unused by C14-i
- 635–638 used and 639–644 unused by L1
- 645, 646 used and 647–654 unused by G1
- 655–664 unused by E1
- 665–674 unused by S11
- 675–684 unused by S12
- 685–694 unused by XP-G21
- 695–704 reserved by C14-j
- 715–717 used and 718–724 unused by CP
- 455, 456 used by S3
- 465 used and 466–474 unused by S4+S8
- 425, 426 used and 427–434 unused by S1
- 435 used and 436–444 unused by S2
- 345–354 reserved by C14: 346 used, 345 refuted, 347–354 unused
- 196–204 unused by C12, 213 and 214 used by `DS-I`, 215 and 216 used by `VA-F`, item 8's reservation (215–224, never published) released from 217 on, 226–234 unused by C15, 241–244 unused by C16, 256–264 unused by C20, 250–254 unused by C21, 267–274 unused by C25, 278–284 unused by C22, 285–294 unused by C24, 295–296 used and 297–304 unused by C23, 305–314 unused by C26, 315 used and 316–324 unused by C27, 325–326 used and 327–334 unused by C28, 189–194 unused by C9
