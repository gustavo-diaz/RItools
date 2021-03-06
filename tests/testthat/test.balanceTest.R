################################################################################
# Tests for balanceTest function
################################################################################
## if working interactively in inst/tests you'll need
## library(RItools, lib.loc = '../../.local')
library("testthat")

context("balanceTest Function")

test_that("xBal univariate descriptive means agree w/ reference calculations",{
    set.seed(20160406)
    n <- 7 
     dat <- data.frame(x1=rnorm(n), x2=rnorm(n),
                        s=rep(c("a", "b"), c(floor(n/2), ceiling(n/2)))
                        )
     dat = transform(dat, z=as.numeric( (x1+x2+rnorm(n))>0 ) )


    lm1 <- lm(x1~z, data=dat)
     xb1 <- balanceTest(z~x1+strata(s), data=dat, report=c("adj.mean.diffs"))
     expect_equal(xb1$results["x1", "adj.diff", "Unstrat"], coef(lm1)["z"], check.attributes=F)

     ## try to match default ETT weighting    
    pihat <- fitted(lm(z~s, data=dat))     
     lm2a <- lm(x1~z+s, data=dat, weights=ifelse(pihat==1,1, (1-pihat)^-1))
     expect_equivalent(xb1$results["x1", "adj.diff", "s"], coef(lm2a)["z"])

    ## a little more explicitly:
    d <- split(dat, dat$s)
    mndiffs <- sapply(d, function(Data) {with(Data, mean(x1[z==1]) - mean(x1[z==0]))})
    cmndiff <- weighted.mean(mndiffs, w = sapply(d, function(Data) sum(Data$z==1)))
    expect_equivalent(xb1$results["x1", "adj.diff", "s"], cmndiff)

})

test_that("xBal inferentials, incl. agreement w/ Rao score test for cond'l logistic regr",{
    library(survival)
    set.seed(20160406)
    n <- 51 # increase at your peril -- clogit can suddenly get slow as stratum size increases
     dat <- data.frame(x1=rnorm(n), x2=rnorm(n),
                        s=rep(c("a", "b"), c(floor(n/2), ceiling(n/2)))
                        )
     dat = transform(dat, z=as.numeric( (x1+rnorm(n))>0 ) )
    
    xb1 <- balanceTest(z~x1+strata(s), data=dat, report=c("z.scores"))
    cl1a <- suppressWarnings( # may warn about non-convergence
        clogit(z~x1, data=dat, iter.max=1) )
     cl1b <- suppressWarnings( clogit(z~x1+strata(s), data=dat, iter.max=1) )

    expect_equivalent(summary(cl1a)$sctest['test'],(xb1$results["x1", "z", "Unstrat"])^2 )
    expect_equivalent(summary(cl1b)$sctest['test'],(xb1$results["x1", "z", "s"])^2 )

    xb2 <- balanceTest(z~x1+x2+strata(s), data=dat, report=c("chisq"))
    cl2a <- suppressWarnings( # may warn about non-convergence
        clogit(z~x1+x2, data=dat, iter.max=1) )
     cl2b <- suppressWarnings( clogit(z~x1+x2+strata(s), data=dat, iter.max=1) )

    expect_equivalent(summary(cl2a)$sctest['test'],(xb2$overall["Unstrat", "chisquare"]) )
    expect_equivalent(summary(cl2b)$sctest['test'],(xb2$overall["s", "chisquare"]) )

    xb3 <- balanceTest(z~w1+w2+strata(s),
                    data=transform(dat, w1=x2+.1*x1, w2=x2-.1*x1),
                    report=c("z.scores", "chisq"))
    expect_equivalent(xb2$overall["Unstrat", "chisquare"], xb3$overall["Unstrat", "chisquare"])
    expect_equivalent(xb2$overall["s", "chisquare"], xb3$overall["s", "chisquare"])

    ## the below documents how the chi-square statistic can be larger than the sum of squared z
    ## statistics.  Unremarkable here, but can be alarming when you see it on the screen (cf #75 ). 
    expect_true(all(colSums(xb3$results[,'z',]^2, na.rm=T) < xb3$overall[,'chisquare']))
}
          )

test_that("Alternate formats for stratum.weights argument", {
    set.seed(20160406)
    n <- 7 # increase at your peril -- clogit gets slow quickly as stratum size increases
    dat <- data.frame(x1=rnorm(n), x2=rnorm(n),
                      s=rep(c("a", "b"), c(floor(n/2), ceiling(n/2)))
                      )
    dat = transform(dat, z=as.numeric( (x1+x2+rnorm(n))>0 ) )

    xb1 <- balanceTest(z~x1+strata(s)-1, data=dat, report="all")

    hwts <- with(dat, colSums(table(z, s)^-1)^-1 ) # 2*harmonic means of (n_{tb}, n_{cb}), not normalized
    xb1a <- balanceTest(z~x1+strata(s)-1, data=dat, stratum.weights=hwts, report="all")
    expect_equal(xb1, xb1a)

    xb2 <- balanceTest(z~x1+strata(s), data=dat, report="all")
    xb2a <- balanceTest(z~x1+strata(s), data=dat, stratum.weights=list(Unstrat=c("1"=1), s=hwts), report="all")
    expect_equal(xb2, xb2a)
    xb2b <- balanceTest(z~x1+strata(s), data=dat, stratum.weights=list(Unstrat=1, s=hwts), report="all")
    expect_equal(xb2, xb2b)
    xb2c <- balanceTest(z~x1+strata(s), data=dat,
                     stratum.weights=list(Unstrat="cheese!", #shouldn't matter in 1-stratum case
                                                   s=hwts), report="all")
    expect_equal(xb2, xb2c)
    xb2d <- balanceTest(z~x1+strata(s), data=dat,
                     stratum.weights=list(Unstrat=NULL, s=hwts), report="all")
    expect_equal(xb2, xb2d)
    xb2e <- balanceTest(z~x1+strata(s), data=dat,
                     stratum.weights=list(s=hwts), report="all")
    expect_equal(xb2, xb2e)

} )
test_that("balanceTreturns covariance of tests", {
  set.seed(20130801)
  n <- 500

  library(MASS)
  xs <- mvrnorm(n,
                mu = c(1,2,3),
                Sigma = matrix(c(1, 0.5, 0.2,
                    0.5, 1, 0,
                    0.2, 0, 1), nrow = 3, byrow = T))

  p <- plogis(xs[,1]- 0.25 * xs[,2] - 1)
  z <- rbinom(n, p = p, size = 1)
  s <- rep(c(0,1), each = n/2)

  dat <- cbind(z, xs, s)


  # we use ETT weighting here to correspond to the weighting scheme used
  # in the descriptives section
  res <- balanceTest(z ~ . + strata(s),
                  data = as.data.frame(dat),
                  stratum.weights = RItools:::effectOfTreatmentOnTreated,
                  report = 'all')

  tcov <- attr(res$overall, "tcov")

  expect_false(is.null(tcov))

  expect_equal(length(tcov), 2)

  ## Developer note: to strip out entries corresponding to intercept -- which has var 0,
  ## except when there's variation in unit weights and/or cluster sizes --
  ## have to filter out rows and cols named "(Intercept)", separately for each
  ## entry in list tcov.  (Recording while updating test that follows, `c(4,4)` --> `c(5,5)`)
  expect_equal(dim(tcov[[1]]), c(5,5))

})

test_that("Passing post.alignment.transform, #26", {
  data(nuclearplants)

  # Identity shouldn't have an effect
  res1 <- balanceTest(pr ~ ., data=nuclearplants)
  res2 <- balanceTest(pr ~ ., data=nuclearplants, post.alignment.transform = function(x) x)

  expect_true(all.equal(res1, res2)) ## allow for small numerical differences

  res3 <- balanceTest(pr ~ ., data=nuclearplants, post.alignment.transform = rank)

  expect_true(all(dim(res1$results) == dim(res3$results)))

  expect_error(balanceTest(pr ~ ., data=nuclearplants, post.alignment.transform = mean),
               "Invalid post.alignment.transform given")

  res4 <- balanceTest(pr ~ ., data=nuclearplants, post.alignment.transform = rank, report="all")
  res5 <- balanceTest(pr ~ ., data=nuclearplants, report="all")

  expect_false(isTRUE(all.equal(res4,res5)))

  # a wilcoxon rank sum test, asymptotic and w/o continuity correction
  res6 <- balanceTest(pr ~ cost, data=nuclearplants, post.alignment.transform = rank,
                   report="all", p.adjust.method='none')

  expect_equal(res6$results["cost", "p", "Unstrat"],
               wilcox.test(cost~pr, data=nuclearplants, exact=FALSE, correct=FALSE)$p.value)

  # w/ one variable, chisquare p value should be same as p value on that variable
  expect_equal(res6$results["cost", "p", "Unstrat"],
               res6$overall["Unstrat","p.value"])

  # to dos: test combo of a transform with non-default stratum weights.

})

test_that("NA in stratify factor are dropped", {
  data(nuclearplants)

  n2 <- nuclearplants
  n2 <- rbind(n2, n2[1,])
  n2$pt[1] <- NA

  f <- function(d) {
    balanceTest(pr ~ . - pt + strata(pt) - 1, data = d)
  }

  xb1 <- f(nuclearplants)
  xb2 <- f(n2)

  expect_equal(xb1, xb2)
})

test_that("Use of subset argument", {
  data(nuclearplants)

  xb1 <- balanceTest(pr ~ . - pt + strata(pt) - 1, data = nuclearplants)
  xb2 <- balanceTest(pr ~ . - pt + strata(pt) - 1, data = nuclearplants, subset=pt<=1)
  expect_equal(xb1, xb2)

  n2 <- nuclearplants
  n2 <- rbind(n2, n2[1,])
  n2[nrow(nuclearplants)+1, "pt"] <- 2

  expect_warning(xb3 <- balanceTest(pr ~ . - pt + strata(pt) - 1, data = n2, subset=pt<=1),
                 "ropped") #if we get rid of warning re dropping levels which did not include
                                        #both treated and control, get rid of expect_warning here too
  expect_equal(xb1, xb3)
})

test_that("Observations not meeting subset condition are retained although downweighted to 0",{

    data(nuclearplants)
    ## first, check assumptions about offsets that are made within the code
    mf0 <- model.frame(cost~date + offset(date<68), data=nuclearplants, offset=(cap>1000))
    expect_equal(sum(names(mf0)=='(offset)'), 1L)
    expect_equivalent(mf0$'(offset)', nuclearplants$cap>1000)
    
    n2 <- nuclearplants
    nuclearplants$pt <- factor(nuclearplants$pt)
    n2 <- rbind(n2, n2[1,])
    n2[nrow(nuclearplants)+1, "pt"] <- 2
    n2$pt <- factor(n2$pt)

    ## this indirect test relies on xBal's dropping unused factor levels
    xb1 <- balanceTest(pr ~ ., data = nuclearplants)
    xb2 <- balanceTest(pr ~ ., data = n2, subset=pt!='2')
    ## confirm that we still see the '2' level, even if it receives no weight
    expect_match(dimnames(xb2$results)[[1]], "pt2", all=FALSE)
    expect_equivalent(xb1$results[,'std.diff',], #only the descriptives should be the same for
                      xb2$results[ dimnames(xb2$results)[[1]]!="pt2" ,'std.diff',]) #these two
    expect_true(is.na(xb2$results[ "pt2" ,'std.diff',]) | # presently this is NA, but
                    xb2$results[ "pt2" ,'std.diff',]==0) # it might ideally be a 0

})


test_that("p.adjust.method argument", {
  data(nuclearplants)

  res.none <- balanceTest(pr ~ . + strata(pt),
                       data = nuclearplants,
                       report = c("p.value", "chisquare"),
                       p.adjust.method = "none")
  
  # the default argument (holm) should cause the p-values to increase
  res.holm <- balanceTest(pr ~ . + strata(pt),
                       data = nuclearplants,
                       report = c("p.value", "chisquare"))
  T_or_NA <- function(vec) {ans <- as.logical(vec) ; ans[is.na(ans)] <- TRUE; ans}
  
  expect_true(all(T_or_NA(res.holm$result[, "p", ] >= res.none$result[, "p", ])))
  expect_true(all(T_or_NA(res.holm$overall[, "p.value"] >= res.none$overall[, "p.value"])))

### with just one covar, holm should do the same as none

    res1.none <- balanceTest(pr ~ cost + strata(pt),
                       data = nuclearplants,
                       report = c("p.value", "chisquare"),
                       p.adjust.method = "none")
  
  res1.holm <- balanceTest(pr ~ cost + strata(pt),
                       data = nuclearplants,
                       report = c("p.value", "chisquare"))

  expect_equal(res1.holm$result[, "p", ], res1.none$result[, "p", ])
  expect_equal(res1.holm$overall[, "p.value"], res1.none$overall[, "p.value"])

})

test_that("NAs properly handled", {
  set.seed(2903934)
  n <- 20
  df <- data.frame(Z = rep(c(0,1), n/2),
                   X1 = rnorm(n),
                   X2 = rnorm(n))
  df$X1[1:3] <- NA

  bt1 <- balanceTest(Z ~ X1, data = df)

  ## issue 92: the following fails
  bt2 <- balanceTest(Z ~ X1 + X2, data = df)
})

## To do: adapt the below to test print.xbal instead of lower level functions
##test_that("printing of NA comparisons is optional",
replicate(0,
{
    set.seed(20130801)

  d <- data.frame(
      x = rnorm(500),
      f = factor(sample(c("A", "B", "C"), size = 500, replace = T)),
      c = rep(1:100, 5),
      s = rep(c(1:4, NA), 100),
      paired = rep(c(0,1), each = 250),
      z = rep(c(0,1), 250))
  d$'(weights)' <- 1

  d$x[sample.int(500, size = 10)] <- NA

  design.flags   <- RItools:::makeDesigns(z ~ x + f + strata(s) + cluster(c), data = d)
  design.noFlags <- RItools:::makeDesigns(z ~ x + f + strata(s), data = d, include.NA.flags = FALSE)

  expect_equal(dim(design.flags@Covariates)[2], 5)
  expect_equal(dim(design.noFlags@Covariates)[2], 4)
})
