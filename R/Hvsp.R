#'  Hierarchical Vintage Sparse PCA (Hvsp)
#'
#' The hierarchical vintage sparse PCA (Hvsp) that combines
#' vintage sparse PCA by Rohe and Zeng (2022) and
#' hierarchical community detection (HCD) by Li et al. (2020).
#'
#' @param A input adjacency matrix. Can be standard R matrix or dsCMatrix (or other type in package Matrix)
#' @param stopping  stopping rule. "NB" (default) -- non-backtracking matrix spectrum, "ECV" -- edge cross-validation, "Fix"-- fixed D layers of partitioning
#' ECV is nonparametric rank evaluation by cross-validation -- a more generally applicable approach
#' without assuming SBM or its variants. Also available for weighted networks.
#' It is believed to be more robust than NB but less effective if the true model is close to BTSBM.
#' ECV is computationally much more intensive.
#' @param n.min  the algorithm will stop splitting if the current size is <= 2*n.min.
#' @param D  the number of layers to partition, if stopping=="Fix".
#' @param notree  if TRUE, will not produce the data.tree object or the community similarity matrix. Only the cluster label and the tree path strings will be returned. This typically makes the runing faster.
#' @param ... optional arguments for vsp()
#' @return Output a \code{HCD} object
#' \describe{
#'  \item{results}{
#'  \describe{
#'  \item{labels}{clustering label}
#'  \item{ncl}{number of clusters}
#'  \item{cluster.tree}{cluster tree from data.tree}
#'  \item{P}{estimated probability matrix}
#'  \item{node.bin.sim.mat}{nodes' similarity matrix}
#'  \item{comm.bin.sim.mat}{clusters' similarity matrix}
#'  \item{tree.path}{nodes' tree path}
#'  }
#'  }
#'  \item{cent}{centrality/importance score for vsp}
#' }
#' @export
#' @examples
#' tt <- BTSBM(1024, 2, c(1, .3, .09), 50)
#' A <- tt$A.list[[1]]
#' Hvsp(A)
#'
#' data(citation)
#' Hvsp(citation)
Hvsp <- function(A, stopping="NB", n.min=25, D = NULL, notree=TRUE, ...) {

  HCD(A,method="vsp", stopping=stopping, reg=FALSE, n.min=n.min, D=D, notree=notree, ...)

}
