#' reconstruct_pattern_homo
#'
#' @description Pattern reconstruction for homogeneous pattern
#'
#' @param pattern ppp object with pattern.
#' @param n_random Integer with number of randomizations.
#' @param e_threshold Double with minimum energy to stop reconstruction.
#' @param max_runs Integer with maximum number of iterations if \code{e_threshold}
#' is not reached.
#' @param no_change Integer with number of iterations at which the reconstruction will
#' stop if the energy does not decrease.
#' @param annealing Double with probability to keep relocated point even if energy
#' did not decrease.
#' @param n_points Integer with number of points to be simulated.
#' @param window owin object with window of simulated pattern.
#' @param comp_fast Integer with threshold at which summary functions are estimated
#' in a computational fast way.
#' @param weights Vector with weights used to calculate energy.
#' The first number refers to Gest(r), the second number to pcf(r).
#' @param r_length Integer with number of intervals from \code{r = 0} to \code{r = rmax} for which
#' the summary functions are evaluated.
#' @param r_max Double with maximum distance used during calculation of summary functions. If \code{NULL},
#' will be estimated from data.
#' @param return_input Logical if the original input data is returned.
#' @param simplify Logical if only pattern will be returned if \code{n_random = 1}
#' and \code{return_input = FALSE}.
#' @param verbose Logical if progress report is printed.
#' @param plot Logical if pcf(r) function is plotted and updated during optimization.
#'
#' @return rd_pat
#'
#' @examples
#' \dontrun{
#' pattern_recon_a <- reconstruct_pattern_homo(species_a, n_random = 19,
#' max_runs = 1000)
#'
#' pattern_recon_b <- reconstruct_pattern_homo(species_a, n_points = 70,
#' n_random = 19, max_runs = 1000)
#' }
#'
#' @aliases reconstruct_pattern_homo
#' @rdname reconstruct_pattern_homo
#'
#' @references
#' Kirkpatrick, S., Gelatt, C.D.Jr., Vecchi, M.P., 1983. Optimization by simulated
#' annealing. Science 220, 671–680. <https://doi.org/10.1126/science.220.4598.671>
#'
#' Tscheschel, A., Stoyan, D., 2006. Statistical reconstruction of random point
#' patterns. Computational Statistics and Data Analysis 51, 859–871.
#' <https://doi.org/10.1016/j.csda.2005.09.007>
#'
#' Wiegand, T., Moloney, K.A., 2014. Handbook of spatial point-pattern analysis in
#' ecology. Chapman and Hall/CRC Press, Boca Raton. ISBN 978-1-4200-8254-8
#'
#' @keywords internal
reconstruct_pattern_homo <- function(pattern,
                                     n_random = 1,
                                     e_threshold = 0.01,
                                     max_runs = 1000,
                                     no_change = Inf,
                                     annealing = 0.01,
                                     n_points = NULL,
                                     window = NULL,
                                     comp_fast = 1000,
                                     weights = c(0.5, 0.5),
                                     r_length = 250,
                                     r_max = NULL,
                                     return_input = TRUE,
                                     simplify = FALSE,
                                     verbose = TRUE,
                                     plot = FALSE){

  # check if n_random is >= 1
  if (n_random < 1) {

    stop("n_random must be >= 1.", call. = FALSE)

  }

  # use number of points  of pattern if not provided
  if (is.null(n_points)) {

    message("> Using number of points 'pattern'.")

    n_points <- pattern$n

  }

  # use window of pattern if not provided
  if (is.null(window)) {

    message("> Using window of 'pattern'.")

    window <- pattern$window

  }

  # calculate intensity
  intensity <- n_points / spatstat.geom::area(window)

  # check if number of points exceed comp_fast limit
  if (n_points > comp_fast) {

    # Print message that summary functions will be computed fast
    if (verbose) {

      message("> Using fast compuation of summary functions.")

    }

    comp_fast <- TRUE

  } else {

    comp_fast <- FALSE

  }

  # set names of randomization randomized_1 ... randomized_n
  names_randomization <- paste0("randomized_", seq_len(n_random))

  # create empty lists for results
  energy_list <- vector("list", length = n_random)
  iterations_list <- vector("list", length = n_random)
  stop_criterion_list <- as.list(rep("max_runs", times = n_random))
  result_list <- vector("list", length = n_random)

  # set names
  names(energy_list) <- names_randomization
  names(iterations_list) <- names_randomization
  names(stop_criterion_list) <- names_randomization
  names(result_list) <- names_randomization

  # check if weights make sense
  if (sum(weights) > 1 || sum(weights) == 0) {

    stop("The sum of 'weights' must be 0 < sum(weights) <= 1.", call. = FALSE)

  }

  # unmark pattern
  if (spatstat.geom::is.marked(pattern)) {

    pattern <- spatstat.geom::unmark(pattern)

    if (verbose) {
      warning("Unmarked provided input pattern. For marked pattern, see reconstruct_pattern_marks().",
              call. = FALSE)

    }
  }

  # calculate r from data
  if (is.null(r_max)) {

    r <- seq(from = 0, to = spatstat.explore::rmax.rule(W = window, lambda = intensity),
             length.out = r_length)

  # use provided r_max
  } else {

    r <- seq(from = 0, to = r_max, length.out = r_length)

  }

  # create Poisson simulation data
  simulated <- spatstat.random::runifpoint(n = n_points, nsim = 1, drop = TRUE,
                                         win = window, warn = FALSE)

  # fast computation of summary functions
  if (comp_fast) {

    gest_observed <- spatstat.explore::Gest(pattern, correction = "none", r = r)

    gest_simulated <- spatstat.explore::Gest(simulated, correction = "none", r = r)

    pcf_observed <- estimate_pcf_fast(pattern, correction = "none",
                                      method = "c", spar = 0.5, r = r)

    pcf_simulated <- estimate_pcf_fast(simulated, correction = "none",
                                       method = "c", spar = 0.5, r = r)

  # normal computation of summary functions
  } else {

    gest_observed <- spatstat.explore::Gest(X = pattern, correction = "han", r = r)

    gest_simulated <- spatstat.explore::Gest(X = simulated, correction = "han", r = r)

    pcf_observed <- spatstat.explore::pcf.ppp(X = pattern, correction = "best",
                                           divisor = "d", r = r)

    pcf_simulated <- spatstat.explore::pcf.ppp(X = simulated, correction = "best",
                                            divisor = "d", r = r)

  }

  # energy before reconstruction
  energy <- (mean(abs(gest_observed[[3]] - gest_simulated[[3]]), na.rm = TRUE) * weights[[1]]) +
    (mean(abs(pcf_observed[[3]] - pcf_simulated[[3]]), na.rm = TRUE) * weights[[2]])

  # create n_random recondstructed patterns
  for (current_pattern in seq_len(n_random)) {

    # current simulated
    simulated_current <- simulated
    energy_current <- energy

    # counter of iterations
    iterations <- 0

    # counter if energy changed
    energy_counter <- 0

    # df for energy
    energy_df <- data.frame(i = seq(from = 1, to = max_runs, by = 1), energy = NA)

    # random ids of pattern
    rp_id <- sample(x = seq_len(simulated_current$n), size = max_runs, replace = TRUE)

    # create random new points
    rp_coords <- spatstat.random::runifpoint(n = max_runs, nsim = 1, drop = TRUE,
                                           win = simulated_current$window,
                                           warn = FALSE)

    # create random number for annealing prob
    if (annealing != 0) {

      random_annealing <- stats::runif(n = max_runs, min = 0, max = 1)

    } else {

      random_annealing <- rep(0, max_runs)

    }

    # pattern reconstruction algorithm (optimaztion of energy) - not longer than max_runs
    for (i in seq_len(max_runs)) {

      # data for relocation
      relocated <- simulated_current

      # get current point id
      rp_id_current <- rp_id[[i]]

      # relocate point
      relocated$x[[rp_id_current]] <- rp_coords$x[[i]]

      relocated$y[[rp_id_current]] <- rp_coords$y[[i]]

      # calculate summary functions after relocation
      if (comp_fast) {

        gest_relocated <- spatstat.explore::Gest(relocated, correction = "none", r = r)

        pcf_relocated <- estimate_pcf_fast(relocated, correction = "none",
                                           method = "c", spar = 0.5, r = r)
      } else {

        gest_relocated <- spatstat.explore::Gest(X = relocated, correction = "han", r = r)

        pcf_relocated <- spatstat.explore::pcf.ppp(X = relocated, correction = "best",
                                                divisor = "d", r = r)

      }

      # energy after relocation
      energy_relocated <- (mean(abs(gest_observed[[3]] - gest_relocated[[3]]), na.rm = TRUE) * weights[[1]]) +
        (mean(abs(pcf_observed[[3]] - pcf_relocated[[3]]), na.rm = TRUE) * weights[[2]])

      # lower energy after relocation
      if (energy_relocated < energy_current || random_annealing[i] < annealing) {

        # keep relocated pattern
        simulated_current <- relocated

        # keep energy_relocated as energy
        energy_current <- energy_relocated

        # set counter since last change back to 0
        energy_counter <- 0

        # plot observed vs reconstructed
        if (plot) {

          # https://support.rstudio.com/hc/en-us/community/posts/200661917-Graph-does-not-update-until-loop-completion
          Sys.sleep(0.01)

          graphics::plot(x = pcf_observed[[1]], y = pcf_observed[[3]],
                         type = "l", col = "black", xlab = "r", ylab = "g(r)")

          graphics::abline(h = 1, lty = 2, col = "grey")

          graphics::lines(x = pcf_relocated[[1]], y = pcf_relocated[[3]], col = "red")

          graphics::legend("topright", legend = c("observed", "reconstructed"),
                           col = c("black", "red"), lty = 1, inset = 0.025)

        }

      # increase counter no change
      } else {

        energy_counter <- energy_counter + 1

      }

      # count iterations
      iterations <- iterations + 1

      # save energy in data frame
      energy_df[iterations, 2] <- energy_current

      # print progress
      if (verbose) {

        if (!plot) {

          Sys.sleep(0.01)

        }

        message("\r> Progress: n_random: ", current_pattern, "/", n_random,
                " || max_runs: ", floor(i / max_runs * 100), "%",
                " || energy = ", round(energy_current, 5), "\t\t",
                appendLF = FALSE)

      }

      # exit loop if e threshold or no_change counter max is reached
      if (energy_current <= e_threshold || energy_counter > no_change) {

        # set stop criterion due to energy
        stop_criterion_list[[current_pattern]] <- "e_threshold/no_change"

        break

      }
    }

    # close plotting device
    if (plot) {

      grDevices::dev.off()

    }

    # remove NAs if stopped due to energy
    if (stop_criterion_list[[current_pattern]] == "e_threshold/no_change") {

      energy_df <- energy_df[1:iterations, ]

    }

    # save results in lists
    energy_list[[current_pattern]] <- energy_df
    iterations_list[[current_pattern]] <- iterations
    result_list[[current_pattern]] <- simulated_current

  }

  # combine to one list
  reconstruction <- list(randomized = result_list, observed = pattern,
                         method = "reconstruct_pattern_homo()",
                         energy_df = energy_list, stop_criterion = stop_criterion_list,
                         iterations = iterations_list)

  # set class of result
  class(reconstruction) <- "rd_pat"

  # remove input if return_input = FALSE
  if (!return_input) {

    # set observed to NA
    reconstruction$observed <- "NA"

    # check if output should be simplified
    if (simplify) {

      # not possible if more than one pattern is present
      if (n_random > 1 && verbose) {

        warning("'simplify = TRUE' not possible for 'n_random > 1'.",
                call. = FALSE)

      # only one random pattern is present that should be returend
      } else if (n_random == 1) {

        reconstruction <- reconstruction$randomized[[1]]

      }
    }

  # return input if return_input = TRUE
  } else {

    # return warning if simply = TRUE because not possible if return_input = TRUE (only verbose = TRUE)
    if (simplify && verbose) {

      warning("'simplify = TRUE' not possible for 'return_input = TRUE'.", call. = FALSE)

    }
  }

  # write result in new line if progress was printed
  if (verbose) {

    message("\r")

  }

  return(reconstruction)
}
