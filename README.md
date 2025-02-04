<!-- README.md is generated from README.Rmd. Please edit that file -->

# Hvsp

<!-- badges: start -->
<!-- badges: end -->

This package implements the Hierarchical Vintage Sparse PCA (`Hvsp`)
methodology and is built upon the [`HCD`
package](https://cran.r-project.org/web/packages/HCD/index.html).

-   `Hvsp()` produces the centrality estimation and regression
    coefficient estimation of the commonly used two-stage procedure.

It also includes functions in the `HCD` package:

-   `HCD()` applies the hierarchical community detection (HCD) by Li et
    al. (2020).
-   `BTSBM()` generates network from the binary tree stochastic block
    model by Li et al. (2020).

## Installation

You can install the development version of `Hvsp` from
[GitHub](https://github.com/cccfran/Hvsp) with:

``` r
if (!require("devtools")){
    install.packages("devtools")
}
devtools::install_github("cccfran/Hvsp")
```

## Example

This is a basic example which shows you how to use `Hvsp` on a network:

``` r
library(Hvsp)

# load a citation network
data(citation)

# apply citation network
Hvsp(citation)
```
