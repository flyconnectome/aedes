# aedes

The **aedes** package provides programmatic access to the in progress
Aedes aegypti connectome dataset. Note that this dataset is still in an
early state of proofreading and annotation and access is currently in a
limited pre-release testing phase as we develop a robust community and
infrastructure.

## Implementation Details

The package is delivered as a thin wrapper around
[fafbseg](https://natverse.org/natverse/fafbseg) with optional
registration for [coconatfly](https://natverse.org/coconatfly). This
will be familiar to users of the
[fancr](https://github.com/flyconnectome/fancr) and
[bancr](https://github.com/flyconnectome/bancr) packages.

As a CAVE package you must have access and an appropriate token
recorded. Metadata for this project is stored in a seatable
web-accessible database accessed via `fafbseg::flytable_*` functions
which are wrapped by this package.

CAVE datasets have a concept of the active `materialisation version`
which defines the state of the segmentation used for analysis.
Alternatively a `timestamp` can be specified to allow an exact point in
time to be used.

## Installation

The package must be installed from github:

``` r
if (!requireNamespace("natmanager", quietly = TRUE)) {
  install.packages("natmanager")
}
natmanager::install(pkgs = "flyconnectome/aedes")
```

You also need to do some additional one time setup.

CAVe

In order to start using flytable, you must get an API token. There
doesn’t seem to be a convenient way to do this from the seatable web
interface but you can get one by calling
[`flytable_set_token()`](https://rdrr.io/pkg/fafbseg/man/flytable_login.html)
with your flytable user and password. This should be a once only step.
Thereafter you should have a `FLYTABLE_TOKEN` environment variable set
in your `.Renviron` file.

``` r
# required 
fafbseg::simple_python()

# Will open browser to get new token
fafbseg::flywire_set_token()
# Writes a known token to correct location
fafbseg::flywire_set_token("2f88e16c4f21bfcb290b2a8288c05bd0")

fafbseg::flytable_set_token()
```

## Setup for coconatfly

We recommend using coconatfly for most analysis. At the moment you must
tell coconatfly about the aedes dataset once per R session.

``` r
library(aedes)
```

``` R
## Loading required package: fafbseg

## Loading required package: nat

## Loading required package: rgl

## Registered S3 method overwritten by 'nat':
##   method             from
##   as.mesh3d.ashape3d rgl

## 
## Attaching package: 'nat'

## The following object is masked from 'package:rgl':
## 
##     wire3d

## The following objects are masked from 'package:base':
## 
##     intersect, setdiff, union

## Run dr_fafbseg() for a status report on your installation
```

``` r
library(coconatfly)

# once per session
register_aedes_coconat()
```

## Examples

``` r
library(dplyr)
```

``` R
## 
## Attaching package: 'dplyr'

## The following objects are masked from 'package:nat':
## 
##     intersect, setdiff, union

## The following objects are masked from 'package:stats':
## 
##     filter, lag

## The following objects are masked from 'package:base':
## 
##     intersect, setdiff, setequal, union
```

``` r
# 1) List neurons with class ALPN
alpn_meta <- cf_meta(cf_ids(aedes = "/class:ALPN"))
```

``` R
## Updating 19 ids

## flywire_rootid_cached: Looking up 19 missing keys

## Updating 245 ids

## flywire_rootid_cached: Looking up 226 missing keys
```

``` r
alpn_meta %>% count(subclass, subsubclass)
```

``` R
##   subclass subsubclass   n
## 1     ALPN      BI_MUL  21
## 2     ALPN      BI_UNI   8
## 3     ALPN      II_MUL 214
## 4     ALPN      II_UNI 329
```

``` r
alpn_meta %>% count(type, side) %>% tidyr::spread(side, n)
```

``` R
##           type   L  M   R
## 1  G0_MD1_ilPN   1 NA   1
## 2  G0_MD1_l2PN   1 NA   1
## 3      G1_ilPN   1 NA   1
## 4       G1_vPN   1 NA   1
## 5    G10_il2PN   1 NA   1
## 6     G10_ppPN   1 NA   1
## 7      G11_lPN   3 NA   4
## 8     G12_lvPN   1 NA   1
## 9    G13_lPN_a   2 NA   1
## 10   G13_lPN_b   3 NA   2
## 11  G13_lvPN_a   2 NA   2
## 12  G13_lvPN_b   2 NA   2
## 13     G14_lPN   1 NA   1
## 14    G15_adPN   1 NA   1
## 15    G16_adPN   1 NA   1
## 16     G18_lPN   1 NA   1
## 17    G19_adPN   2 NA   2
## 18      G2_lPN   1 NA   1
## 19     G20_lPN   2 NA   2
## 20     G21_lPN   3 NA   3
## 21    G22_adPN   1 NA   1
## 22     G23_lPN   3 NA   3
## 23     G24_lPN   2 NA   2
## 24     G25_lPN   1 NA   1
## 25     G26_lPN   1 NA   1
## 26    G27_adPN   1 NA   1
## 27    G28_adPN   1 NA   1
## 28    G29_adPN   1 NA   1
## 29    G29_lvPN   1 NA  NA
## 30     G3_adPN   1 NA   1
## 31      G3_vPN   1 NA   1
## 32    G30_adPN   1 NA   1
## 33     G31_lPN   4 NA   3
## 34   G32_lPN_a   4 NA   5
## 35   G32_lPN_b   4 NA   5
## 36     G33_lPN   5 NA   5
## 37     G34_lPN   1 NA   1
## 38     G35_lPN   1 NA   2
## 39     G35_vPN   2 NA   1
## 40    G36_adPN   2 NA   2
## 41     G36_vPN   2 NA   2
## 42    G37_adPN   1 NA   1
## 43    G38_adPN   2 NA   2
## 44    G39_adPN   2 NA   2
## 45      G4_lPN   1 NA   1
## 46    G40_adPN   2 NA   2
## 47    G40_lvPN   6 NA   6
## 48    G41_adPN   1 NA   2
## 49    G41_lvPN   1 NA   1
## 50    G42_adPN   1 NA   1
## 51    G43_adPN   1 NA   1
## 52    G44_adPN   3 NA   2
## 53    G45_adPN   1 NA   2
## 54     G46_lPN   3 NA   3
## 55     G47_lPN   2 NA   2
## 56    G48_adPN   2 NA   2
## 57     G48_vPN   1 NA   1
## 58     G49_lPN   4 NA   4
## 59     G49_vPN   1 NA   1
## 60     G5_adPN   1 NA   1
## 61    G50_adPN   1 NA   1
## 62    G51_adPN   2 NA   3
## 63    G52_adPN   2 NA   2
## 64     G53_lPN   1 NA   1
## 65     G53_vPN   9 NA   4
## 66    G54_adPN   3 NA   3
## 67    G56_adPN   2 NA   2
## 68    G57_adPN   1 NA   1
## 69    G58_adPN   1 NA   1
## 70    G59_adPN   3 NA   1
## 71     G59_vPN   2 NA   2
## 72    G60_adPN   1 NA   3
## 73     G61_lPN   2 NA   3
## 74     G62_lPN   1 NA   1
## 75     G63_lPN   3 NA   2
## 76     G64_lPN   2 NA   2
## 77    G65_adPN   1 NA   1
## 78    G66_adPN   2 NA   2
## 79    G67_adPN   2 NA   2
## 80    G68_adPN   1 NA   1
## 81    G69_adPN   2 NA   1
## 82     G7_adPN   5 NA   6
## 83    G70_lvPN   1 NA   1
## 84     G71_lPN   3 NA   2
## 85    G72_adPN   1 NA   1
## 86    G73_adPN   1 NA   1
## 87    G74_adPN   1 NA   1
## 88    G75_adPN   2 NA   2
## 89    G76_adPN   1 NA   1
## 90     G8_adPN   1 NA   1
## 91     G8_lvPN   1 NA  NA
## 92      G8_vPN   3 NA   2
## 93     G9_adPN   1 NA   1
## 94        <NA> 117  2 116
```

Select a smaller set of PN neurons with type matching G2X

``` r
gpn_ids <- cf_meta(cf_ids(aedes = "/type:G2[0-9].*PN"))
```

``` R
## Updating 3 ids

## Updating 245 ids
```

``` r
gpn_meta <- cf_meta(gpn_ids)
```

``` R
## Updating 245 ids
```

``` r
gpn_meta %>% count(type, side) %>% tidyr::spread(side, n)
```

``` R
##        type L  R
## 1   G20_lPN 2  2
## 2   G21_lPN 3  3
## 3  G22_adPN 1  1
## 4   G23_lPN 3  3
## 5   G24_lPN 2  2
## 6   G25_lPN 1  1
## 7   G26_lPN 1  1
## 8  G27_adPN 1  1
## 9  G28_adPN 1  1
## 10 G29_adPN 1  1
## 11 G29_lvPN 1 NA
```

Now we can cluster by connectivity. This depends on partner neurons
having some kind of identity recorded, typically via the type column
(the default) or the numeric group column (which is often set even when
a formal type has not been proposed). At the time of writing PN input
partners (ORNs) are well typed but downstream partners less so. So let’s
just use input partners and also restrict to neurons that have already
been typed with n=2 neurons in the type so that we have a small plot.

``` r
gpn_meta %>% 
  add_count(type) %>% 
  filter(n==2) %>% 
  cf_cosine_plot(partners = 'in')
```

``` R
## Updating 245 ids
## Updating 245 ids

## Warning in coconat::partner_summary2adjacency_matrix(x[["inputs"]], inputcol =
## groupcol, : Dropping: 940/1320 neurons representing 12245/27020 synapses due to
## missing ids!

## Updating 245 ids
```

![](reference/figures/README-unnamed-chunk-3-1.png)

There are a wealth of options for the clustering. You can select input
partners only or using the group column rather than type for defining
the neuron-type connectivity matrix. You can turn off partner grouping
(which can actually work better in some circumstances when there is
limited partner type information available) but you will not be able to
co-cluster L and R homologues.

``` r
cf_cosine_plot(gpn_ids, heatmap = T, partners = 'in')
cf_cosine_plot(gpn_ids, heatmap = T, partners = 'in', group = 'group')
cf_cosine_plot(gpn_ids, heatmap = T, partners = 'in', group = FALSE)
```

The default threshold setting of 5 synapse may be a little restrictive
for this dataset where synapses counts seem to be low (even without
considering proofreading).

``` r
cf_cosine_plot(gpn_ids, heatmap = T, partners = 'in', group = FALSE, threshold = 2)
```

``` R
## Updating 245 ids
## Updating 245 ids
## Updating 245 ids
```

![](reference/figures/README-unnamed-chunk-5-1.png)

## Notes

- Access to the Aedes segmentation depends on your CAVE dataset
  permissions.
- Some functions require access to the FlyTable
