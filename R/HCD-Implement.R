#' @import Matrix
#' @import RSpectra
#' @import data.tree
#' @import data.table
#' @import methods
#' @import stringr
#' @import vsp
#' @importFrom dendextend is.dendrogram nnodes
#' @importFrom randnet ECV.Rank SBM.estimate
#' @importFrom irlba irlba
#' @importFrom stats dendrapply kmeans runif
NULL

## the spectral check of non-backtracking matrix for stopping rule
NB.check <- function(A){
  d <- colSums(A)
  n <- nrow(A)
  I <- as(diag(rep(1,n)),"dgCMatrix")
  D <- as(diag(d),"dgCMatrix")
  r <- sqrt(sum(d^2)/sum(d)-1)
  B <- as(matrix(0,nrow=2*n,ncol=2*n),"dgCMatrix")
  B[(n+1):(2*n),1:n] <- -1*I
  B[1:n,(n+1):(2*n)] <- D-I
  B[(n+1):(2*n),(n+1):(2*n)] <- A
  ss <- Re(eigs(B,k=2,which="LM")$values)
  return(sum(abs(ss)>r)>1)
}




### nonparametric rank evaluation by cross-validation -- a more generally applicable approach
## without assuming SBM or its variants. Also available for weighted networks.
## Believe to be more robust than NB but less effective if the true model is close to BTSBM.
## Computationally more intensive.
ECV.check <- function(A,B=3,weighted=FALSE){
  ecv <- ECV.Rank(A, max.K=2, B = 3, holdout.p = 0.1, weighted = weighted,mode="undirected")
  if(weighted){
    if(ecv$sse.rank>1){
      return(TRUE)
    }else{
      return(FALSE)
    }
  }else{
    if(ecv$auc.rank > 1){
      return(TRUE)
    }else{
      return(FALSE)
  }
  }
}

## some functions to handle tree structures

partition_leaves <- function(dend, ...) {
  if (!is.dendrogram(dend)) stop("'dend' is not a dendrogram")

  nodes_labels <- vector("list", length = nnodes(dend))

  i_counter <- 0
  push_node_labels <- function(dend_node) {
    i_counter <<- i_counter + 1

    nodes_labels[[i_counter]] <<- labels(dend_node)
    return(NULL)
  }
  dendrapply(dend, push_node_labels)

  return(nodes_labels)
}


count.edge.dend <- function(dend){
  sort_a_character <- function(dend) dend %>% as.character %>% sort

  bp1 <- partition_leaves(dend)
  bp1 <- lapply(bp1, sort_a_character)
  return(length(bp1))

}

Scaled.Frob <- function(D1,D2){
  scaled.diff <- (D1-D2)*log(1+2*D1)
  return(sqrt(sum(scaled.diff^2)/2))
}


Normalized.Scaled.Frob <- function(D1,D2){
  d.max <- max(D1)
  scaled.diff <- (D1-D2)*log(1+2*D1)/log(1+d.max)
  return(sqrt(sum(scaled.diff^2)/2))
}


Scaled.FP <- function(G1,G2,D1){
  upper.index <- which(upper.tri(G1))
  g1 <- G1[upper.index]
  g2 <- G2[upper.index]
  d1 <- D1[upper.index]
  same.clust.index <- which(g2==1)
  scaled.FP <- sum((1-g1[same.clust.index])*log(2*d1[same.clust.index]+1))
  scaled.FP <- scaled.FP/length(same.clust.index)
  return(scaled.FP)
}

Standard.FP <- function(G1,G2,D1){
  upper.index <- which(upper.tri(G1))
  g1 <- G1[upper.index]
  g2 <- G2[upper.index]
  d1 <- D1[upper.index]
  same.clust.index <- which(g2==1)
  scaled.FP <- sum((1-g1[same.clust.index]))
  scaled.FP <- scaled.FP/length(same.clust.index)
  return(scaled.FP)
}



Scaled.FN <- function(G1,G2,D2){
  upper.index <- which(upper.tri(G1))
  g1 <- G1[upper.index]
  g2 <- G2[upper.index]
  d2 <- D2[upper.index]
  diff.clust.index <- which(g2==0)
  scaled.FN <- sum((g1[diff.clust.index])*exp(2*d2[diff.clust.index]+1))
  scaled.FN <- scaled.FN/length(diff.clust.index)
  return(scaled.FN)
}



Binary.Similarity <- function(s1,s2){
  n <- min(length(s1),length(s2))
  min(which(s1[1:n]!=s2[1:n]))
}


gen.A.from.P <- function(P,undirected=TRUE){
  n <- nrow(P)
  if(undirected){
  upper.tri.index <- which(upper.tri(P))
  tmp.rand <- runif(n=length(upper.tri.index))
  #A <- matrix(0,n,n)
  A <- rsparsematrix(n,n,0)
  A[upper.tri.index[tmp.rand<P[upper.tri.index]]] <- 1
  A <- A+t(A)
  diag(A) <- 0
  return(A) }else{
    A <- matrix(0,n,n)
    r.seq <- runif(n=length(P))
    A[r.seq < as.numeric(P)] <- 1
    diag(A) <- 0
    return(A)
  }
}

#' Binary Tree Stochastic Block Models (BTSBM)
#'
#' Simulated network from BTSBM.
#'
#' @param n dimension of the network
#' @param d number of layers until leaves (excluding the root)
#' @param a.seq sequence a_r
#' @param lambda average node degree, only used when alpha is not provided.
#' @param alpha the common scaling of the a_r sequence, so at the end, essentially the a_r sequence is a.seq*alpha
#' @param N number of networks one wants to generate from the same model
#' @return Output a \code{HCD} object
#' \describe{
#'  \item{A.list}{list of simulated networks}
#'  \item{B}{clusters' probability matrix}
#'  \item{label}{cluster label}
#'  \item{P}{nodes' probability matrix}
#'  \item{comm.sim.mat}{clusters' similarity matrix}
#'  \item{node.sim.mat}{nodes' similarity matrix}
#' }
#' @export
#' @examples
#' \dontrun{
#' BTSBM(1024, 2, c(1, .3, .09), 50)
#' }
BTSBM <- function(n,d,a.seq,lambda,alpha=NULL,N=1){
  K <- 2^d
  #outin <- beta
  #beta <- (2*K*outin/(K-1))^((1/((d-1))))
  ## generate binary strings
  b.list <- list()
  for(k in 1:K){
    b.list[[k]] <- as.character(intToBits(k-1))[d:1]
  }
  ## construct B
  comm.sim.mat <- B <- matrix(0,K,K)
  for(i in 1:(K-1)){
    for(j in (i+1):K){
      s <- Binary.Similarity(b.list[[i]],b.list[[j]])-1
      comm.sim.mat[i,j] <- s+1
    }
  }
  comm.sim.mat <- comm.sim.mat+t(comm.sim.mat)
  diag(comm.sim.mat) <- d+1
  B[1:(K^2)] <- a.seq[d+2-as.numeric(comm.sim.mat)]
  w <- floor(n/K)
  g <- c(rep(seq(1,K),each=w),rep(K,n-w*K))
  Z <- matrix(0,n,K)
  Z[cbind(1:n,g)] <- 1
  P <- Z%*%B%*%t(Z)
  if(is.null(alpha)){
    P <- P*lambda/mean(colSums(P))
  }else{
    P <- P*alpha
  }
  node.sim.mat <- Z%*%comm.sim.mat%*%t(Z)
  diag(node.sim.mat) <- 0
  #print(paste("Within community expected edges: ",P[1,1]*w,sep=""))
  A.list <- list()
  for(I in 1:N){
    A.list[[I]] <- gen.A.from.P(P,undirected=TRUE)
  }
  ret_list <- list(A.list=A.list,B=B,label=g,P=P,comm.sim.mat=comm.sim.mat,node.sim.mat=node.sim.mat)
  class(ret_list) <- "BTSBM"

  return(ret_list)
}





#' Hierarchical community detection (HCD)
#'
#' The hierarchical community detection (HCD) by Li et al. (2020).
#'
#' @param A input adjacency matrix. Can be standard R matrix or dsCMatrix (or other type in package Matrix)
#' @param method  splitting method. "SS" (default) -- sign splitting, "SC" -- spectral clustering, "vsp" -- vintage sparse PCA
#' @param stopping  stopping rule. "NB" (default) -- non-backtracking matrix spectrum, "ECV" -- edge cross-validation, "Fix"-- fixed D layers of partitioning
#' ECV is nonparametric rank evaluation by cross-validation -- a more generally applicable approach
#' without assuming SBM or its variants. Also available for weighted networks.
#' It is believed to be more robust than NB but less effective if the true model is close to BTSBM.
#' ECV is computationally much more intensive.
#' @param reg  whether regularization is needed.
#' Set it to be TRUE will add reguarlization, which help the performance on sparse networks, but it will make the computation slower.
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
#' \dontrun{
#' tt <- BTSBM(1024, 2, c(1, .3, .09), 50)
#' A <- tt$A.list[[1]]
#' HCD(A)
#'
#' data(citation)
#' HCD(citation, method="SS", stopping="NB", notree=F)
#' }
HCD <- function(A,method="SS", stopping="NB",reg=FALSE,n.min=25,D=NULL,notree=TRUE, ...){
  n <- nrow(A)
  ncl <- 0
  xi.loc.labels <- list()
  if(!any(c("SS","SC","vsp")==method)){
    stop("method can only by one of 'SS', 'SC' or 'vsp'")
  }
  if(!any(c("NB","ECV","Fix")==stopping)){
    stop("stopping can only by one of 'NB','ECV' and 'Fix'")
  }
  message("Begin clustering....")
  clusters <- break.cl.sp(f=A,method=method, xi.loc.labels=xi.loc.labels, ncl=ncl, cl.labels=1:n,BH=stopping,reg=reg,n.min=n.min,D=D,...)

  ncl <- clusters$ncl
  xi.loc.labels <- clusters$xi.loc.labels
  labels = rep(0, n)
  for(i in 1:ncl) {
    labels[xi.loc.labels[[i]]] <- i
  }
  tree.path <- clusters$tree.path
  if(!notree){
    message("Finished clustering. Summarizing tree structure....")
    node.tree.path <- strsplit(tree.path,"/")
    suppressWarnings(node.index <- which(unlist(lapply(node.tree.path,function(x) sum(!is.na(as.numeric(x)))>0)))) ### find which path string is for individual nodes
    suppressWarnings(node.number <- unlist(lapply(node.tree.path,function(x) as.numeric(x)[which(!is.na(as.numeric(x)))]))) ### find the specific node name. The non-node string will be removed
    node.dt <- data.table(node.number=node.number,node.index=node.index)
    node.dt2 <- unique(node.dt, by = "node.number")
    node.index <- node.dt2$node.index[sort(node.dt2$node.number,index.return=TRUE)$ix]
    #Binary.Similarity(node.tree.path[[node.index[1]]],node.tree.path[[node.index[1000]]])
    representers <- rep(0,ncl)
    for(i in 1:ncl){
      representers[i] <- which(labels==i)[1]
    }
    community.bin.sim.mat <- matrix(0,ncl,ncl)
    for(i in 1:ncl){
      for(j in 1:ncl){
        if(i==j){
          community.bin.sim.mat[i,i] <- length(node.tree.path[[node.index[representers[i]]]])
        }else{
          community.bin.sim.mat[i,j] <- Binary.Similarity(node.tree.path[[node.index[representers[i]]]],node.tree.path[[node.index[representers[j]]]])
          community.bin.sim.mat[j,i] <- community.bin.sim.mat[i,j]
        }
      }
    }

    Z.mat <- matrix(0,n,ncl)
    Z.mat[cbind(1:n,labels)] <- 1
    node.bin.sim.mat <- Z.mat%*%community.bin.sim.mat%*%t(Z.mat)
    diag(node.bin.sim.mat) <- 0

    tree.path <- paste("All",tree.path,sep="/")
    tree.df <- data.frame(V1=1:length(tree.path),pathString=tree.path)
    #print(tree.path)
    tree.df$pathString <- as.character(tree.df$pathString)
    cluster.tree <- as.Node(tree.df)
  }else{
    cluster.tree <- NULL
    node.bin.sim.mat <- NULL
    community.bin.sim.mat <- NULL
  }
  P.est <- SBM.estimate(A,labels)
  result_list <- list(labels=labels,
                      ncl=ncl,
                      cluster.tree=cluster.tree,
                      P=P.est,
                      node.bin.sim.mat=node.bin.sim.mat,
                      comm.bin.sim.mat=community.bin.sim.mat,
                      tree.path=tree.path)
  result <- list(result = result_list)
  class(result) <- "HCD"
  if(method == "vsp") {
    result <- list(result = result_list,
                   cent = clusters$cent)
    class(result) <- "Hvsp"
  }

  return(result)
}


## cl.labels is the current node index involved in the function call - this is by sign splitting
## use D = maximum level of splitting if want to use HCD-Sign by fixed D with BH is other than "NB" or "ECV"
break.cl.sp = function(f, method="SS",xi.loc.labels, ncl, cl.labels,BH="NB",reg=FALSE,n.min=25,D=NULL,cent=NULL,cent.tmp=NULL, ...) {
  nisol = which(rowSums(f) > 0)
  isol = which(rowSums(f) == 0)
  cl.labels.full <- cl.labels
  ## sanity check -- do not start if there are too many isolated nodes
  if((length(nisol)<=8)||(length(isol)>=5*length(nisol))||(length(nisol)<2*n.min)){
    ncl = ncl + 1
    xi.loc.labels[[ncl]] = cl.labels
    cent[[ncl]] = cent.tmp
    tree.path <- c("",as.character(cl.labels))
    mod.path <- c(0,rep(0,length(cl.labels)))
    if(length(isol)>0) tree.path <- c(tree.path,as.character(cl.labels[isol]))
    message('Too few connected nodes, not even started!')
    return(list(xi.loc.labels = xi.loc.labels, ncl = ncl,tree.path=tree.path,mod.path=mod.path, cent=cent))
  }
  #print(paste(length(isol),"isolated nodes",cl.labels[isol]))
  all.deg = rowSums(f)
  f = f[nisol, nisol] ### only focus on non-isolated nodes - isolated nodes with be attached to the smaller child
  cl.labels.full <- cl.labels
  all.deg = all.deg[nisol]
  cl.labels = cl.labels[nisol]
  n1 = dim(f)[1]

  K = 2
  split.flag <- FALSE
  if(BH=="NB"){
    split.flag <- NB.check(f)
  }else{
    if(BH=="ECV"){
      split.flag <- ECV.check(f)
    }else{
      split.flag <- (D>0)
    }
  }

  if(split.flag) {
    if(reg){
      f.reg <- f + 0.1*mean(all.deg)/nrow(f)
      eig.nf = irlba(f.reg, nu = 2, nv = 2)
    }else{
      eig.nf = irlba(f, nu = 2, nv = 2)
    }
    if(method=="SS"){
      clustering <- rep(0,length(eig.nf$v[,2]))
      clustering[eig.nf$v[,2]<=0] <- 1
      clustering[eig.nf$v[,2]>0] <- 2
    } else if (method == "vsp") {
      eig.nf <- vsp(f, rank = 2, center = F)
      clustering <- apply(eig.nf$Y, 1, function(x) which.max(abs(x)))
    } else{
      if(method=="SC"){
        clustering <- kmeans(eig.nf$v[,1:2],centers=2,iter.max=30,nstart=10)$cluster
      }
    }
    clus = list(clustering=clustering)

    xi.f = clus$clustering
    xi.labels = lapply(1:2, function(x){which(xi.f == x)})

    smaller.cluster <- xi.labels[[which.min(sapply(xi.labels,length))]]
    f1 <- f[smaller.cluster,smaller.cluster]
    a1.labels <- cl.labels[smaller.cluster]
    cent1 <- NULL
    if(method == "vsp") cent1 <- eig.nf$Y[smaller.cluster,which.min(sapply(xi.labels,length))]
    if(length(dim(f1)) > 0) {
      n1 <- dim(f1)[1]
    } else if(length(f1) > 0) { ### case when only 1 node is in this cluster, make it 2, so the later on rank check code still works
      n1 <- 1
    } else {
      n1 = 0
    }
    if(n1 > 2*n.min) { ## only do further clustering on cluster larger  2*n.min
      res = break.cl.sp(f1, method, xi.loc.labels, ncl, a1.labels,BH,reg=reg,n.min,D=D-1,cent=cent,cent.tmp=cent1,...)
      xi.loc.labels = res$xi.loc.labels
      ncl = res$ncl
      L.tree.path <- res$tree.path
      cent = res$cent
      if(length(isol)>0){
        xi.loc.labels[[ncl]] = c(xi.loc.labels[[ncl]],cl.labels.full[isol]) ### attached the isolated nodes in this level with the clusters under the smaller split

        path.head <- L.tree.path[length(L.tree.path)]
        path.head <- gsub('[[:digit:]]+', '', path.head)
        iso.path <- paste(path.head,cl.labels.full[isol],sep="")
        L.tree.path <- c(L.tree.path,iso.path)
      }

      L.mod.path <- res$mod.path

    } else {
      ncl = ncl + 1
      xi.loc.labels[[ncl]] = a1.labels
      cent[[ncl]] = cent1
      if(length(isol)>0) xi.loc.labels[[ncl]] = c(cl.labels.full[isol],xi.loc.labels[[ncl]])
      L.tree.path <- as.character(xi.loc.labels[[ncl]])
      L.mod.path <- rep(0,length(xi.loc.labels[[ncl]]))
      #print('Too small left cluster, Branch End')
    }
    f2 = f[-smaller.cluster, -smaller.cluster]

    a2.labels = cl.labels[-smaller.cluster]
    cent2 <- NULL
    if(method == "vsp") cent2 <- eig.nf$Y[-smaller.cluster, -which.min(sapply(xi.labels,length))]
    if(length(dim(f2)) > 0) {
      n1 <- nrow(f2)

    } else if(length(f2) > 0) {
      n1 <- 1
    } else {
      n1 <- 0
    }
    if(n1 > 2*n.min) {
      res = break.cl.sp(f2, method, xi.loc.labels, ncl, a2.labels,BH,reg=reg,n.min,D=D-1,cent=cent,cent.tmp=cent2, ...)
      xi.loc.labels = res$xi.loc.labels
      R.tree.path <- res$tree.path
      R.mod.path <- res$mod.path
      ncl = res$ncl
      cent = res$cent

    } else {
      ncl = ncl + 1
      xi.loc.labels[[ncl]] = a2.labels
      cent[[ncl]] = cent2
      R.tree.path <- as.character(a2.labels)
      R.mod.path <- rep(0,length(a2.labels))
      #print('Too small right cluster, Branch End')
    }
    L.tree.path <- paste("L",L.tree.path,sep="/")
    R.tree.path <- paste("R",R.tree.path,sep="/")
    tree.path <- c("",L.tree.path,R.tree.path)

  } else {
    ncl = ncl + 1
    xi.loc.labels[[ncl]] = cl.labels
    cent[[ncl]] = cent.tmp
    if(length(isol)>0) xi.loc.labels[[ncl]] = c(cl.labels.full[isol],cl.labels)
    tree.path <- c("",as.character(cl.labels))
    if(length(isol)>0) tree.path <- c(tree.path,as.character(cl.labels.full[isol]))
    #print('One cluster, Branch End, not even started!')
  }
  return(list(xi.loc.labels = xi.loc.labels, ncl = ncl,tree.path=tree.path, cent = cent))
}
