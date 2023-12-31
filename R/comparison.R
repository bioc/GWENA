utils::globalVariables(c("coherence", "avg.contrib", "avg.cor", "avg.weight",
                         "cor.contrib", "cor.cor", "cor.degree"))
#' Calculating Z summary
#'
#' Use the topological metrics and permutations from output of
#' \code{\link[NetRep]{modulePreservation}} to compute a Z summary (a composite
#' preservation statistic) as defined by
#' \href{Langfelder et al. (2011)}{https://doi.org/10.1371/journal.pcbi.1001057}
#'
#' @param observed_stat matrix, bidimensional matrix containing the topological
#' matrix computed for each module by \code{\link[NetRep]{modulePreservation}}
#' (the element \code{observed}). Modules are in row, metrics are in column.
#' @param permutations_array matrix, tridimensional matrix containing the
#' topological matrix computed for each module by
#' \code{\link[NetRep]{modulePreservation}} (the element \code{observed}).
#' Modules are in dim 1, metrics are in dim 2, permutations are in dim 3.
#'
#' @details The original Zsummary composite preservation statistic was defined
#' by Langfelder et al. (2011). However this method use the metric from
#' \code{\link[NetRep]{modulePreservation}} since they it handle better large
#' and multiple testing correction.
#'
#' @importFrom magrittr %>%
#' @importFrom dplyr select
#' @importFrom stats sd median
#'
#' @examples
#' expr_by_cond <- list(cond1 = kuehne_expr[1:24, 1:350],
#'                      cond2 = kuehne_expr[25:48, 1:350])
#' net_by_cond <- lapply(expr_by_cond, build_net, cor_func = "spearman",
#'                       n_threads = 1, keep_matrices = "both")
#'
#' mods_labels <- setNames(
#'   sample(1:6, 350, replace = TRUE,
#'          prob = c(0.05, 0.4, 0.25, 0.15, 0.1, 0.05)),
#'   colnames(expr_by_cond$cond1))
#'
#' netrep_res <- NetRep::modulePreservation(
#'   network = lapply(net_by_cond, `[[`, "adja_mat"),
#'   data = lapply(expr_by_cond, as.matrix),
#'   correlation = lapply(net_by_cond, `[[`, "cor_mat"),
#'   moduleAssignments = mods_labels,  nPerm = 100)
#'
#' z_summary(netrep_res$observed, netrep_res$nulls)
#'
#' mod_by_cond <- mapply(detect_modules, expr_by_cond,
#'                       lapply(net_by_cond, `[[`, "network"),
#'                       MoreArgs = list(detailled_result = TRUE),
#'                       SIMPLIFY = FALSE)
#'
#' comparison <- compare_conditions(expr_by_cond,
#'                                  lapply(net_by_cond, `[[`, "adja_mat"),
#'                                  lapply(net_by_cond, `[[`, "cor_mat"),
#'                                  lapply(mod_by_cond, `[[`, "modules"),
#'                                  n_perm = 100)
#'
#' z_summary(comparison$result$cond1$cond2$observed,
#'           comparison$result$cond1$cond2$nulls)
#'
#' @return A named vector of the z summary statistic with the module id as name.
#'
#' @export

z_summary <- function(observed_stat, permutations_array) {
  # Checks
  if (!is.matrix(observed_stat))
    stop("observed_stat must be a matrix")
  if (!is.numeric(observed_stat))
    stop("observed_stat must only contain numeric values")
  if (!is.array(permutations_array))
    stop("permutations_array must be an array")
  if (length(dim(permutations_array)) != 3)
    stop("permutations_array must be a tridimensional array")
  if (!is.numeric(permutations_array))
    stop("permutations_array must only contain numeric values")

  # Calculating the Z score for each stat
  mean_perm <- apply(permutations_array, c(1,2), mean)
  sd_perm <- apply(permutations_array, c(1,2), stats::sd)
  z_stats <- (observed_stat - mean_perm) / sd_perm

  # Density Z score
  z_density <- z_stats %>%
    as.data.frame %>%
    dplyr::select(coherence, avg.contrib, avg.cor, avg.weight) %>%
    apply(1, stats::median)

  # Connectivity Z score
  z_connectivity <- z_stats %>%
    as.data.frame %>%
    dplyr::select(cor.contrib, cor.cor, cor.degree) %>%
    apply(1, stats::median)

  # Summary Z score
  return(mapply(mean, z_density, z_connectivity))
}


#' Compare modules topology between conditions
#'
#' Take modules built from multiples conditions and search for preservation,
#' non-preservation or one of them, against one or mutliple conditions of
#' reference. Use 7 topological features to perform the differents test, and
#' use permutation to validate results.
#'
#' @param data_expr_list list of matrix or data.frame or SummarizedExperiment,
#' list of expression data by condition, with genes as column and samples as
#' row.
#' @param adja_list list of adjacency matrices, list of square tables by
#' condition, representing connectivity between each genes as returned by
#' build_net.
#' @param cor_list list of matrices and/or data.frames, list of square tables
#' by condition, representing correlation between each gene. Must be the same
#' used to create networks in \code{\link{build_net}}. If NULL, will be
#' re-calculated according to \code{cor_func}.
#' @param modules_list list of modules or nested list of modules, list of
#' modules in one condition (will be considered as the one from reference) or
#' a condition named list with list of modules built in each one.
#' @param ref string or vector of strings, condition(s) name to be used as
#' reference for permutation tests, or "cross comparison" if you want to
#' compare each condition with the other as reference. Default will be the
#' name of the first element in data_expr_list.
#' @param test string or vector of strings, condition(s) name to be tested for
#' permutation tests. If NULL, all conditions except these in ref will be
#' taken. If ref is set to "cross comparison", any test specified will be
#' ignored.
#' @param cor_func string, name of the correlation function to be used. Must be
#' one of "pearson", "spearman", "bicor", "other". If "other", your_func must
#' be provided
#' @param your_func function returning correlation values. Final values must be
#' in [-1;1]
#' @param n_perm integer, number of permutation, meaning number of random gene
#' name re-assignment inside network to compute all tests and statistics for
#' module comparison between condition.
#' @param test_alternative_hyp string, either "greater", "less" or "two.sided".
#' Alternative hypothesis (H1) used for the permutation test. Determine if the
#' metrics computed on permuted values are expected to be greater, less or both
#' than the observed ones. More details:\code{\link[NetRep]{modulePreservation}}
#' @param pvalue_th decimal, threshold of pvalue below which
#' test_alternative_hyp is considered significant. If "two.sided", then
#' pvalue_th is splitted in two for each side (preserved/not preserved).
#' @param n_threads integer, number of threads that can be used to paralellise
#' the computing
#' @param ... any other parameter compatible with
#' \code{\link[NetRep]{modulePreservation}}
#'
#' @details
#' \describe{
#'   \item{Conditions will be based on names of data_expr_list. Please do not
#'   use numbers for conditions names as modules are often named this way}
#'   \item{The final comparison output is a combination of the permutation
#'   test and the Z summary statistic. Comparison value is set to "preserved"
#'   when both return "preserved", "moderately preserved" when Z summary return
#'   it, "unpreserved" when permutation test is not significant and Z summary
#'   return "unpreserved", and "inconclusive" when the two values are opposite}
#'   \item{To avoid recalculation, correlations matrices can be obtain by
#'   setting \code{keep_cor_mat} in \code{\link[GWENA]{build_net}} to TRUE.}
#'   \item{Description of the 7 topological features used for preservation
#'   testing is available in \code{\link[NetRep]{modulePreservation}}.}
#' }
#'
#' @importFrom NetRep modulePreservation
#' @importFrom magrittr %>%
#' @importFrom purrr compact
#' @importFrom stats setNames
#' @importFrom methods is
#'
#' @examples
#' expr_by_cond <- list(cond1 = kuehne_expr[1:24, 1:350],
#'                      cond2 = kuehne_expr[25:48, 1:350])
#' net_by_cond <- lapply(expr_by_cond, build_net, cor_func = "spearman",
#'                       n_threads = 1, keep_matrices = "both")
#' mod_by_cond <- mapply(detect_modules, expr_by_cond,
#'                       lapply(net_by_cond, `[[`, "network"),
#'                       MoreArgs = list(detailled_result = TRUE),
#'                       SIMPLIFY = FALSE)
#' comparison <- compare_conditions(expr_by_cond,
#'                                  lapply(net_by_cond, `[[`, "adja_mat"),
#'                                  lapply(net_by_cond, `[[`, "cor_mat"),
#'                                  lapply(mod_by_cond, `[[`, "modules"),
#'                                  n_perm = 100)
#'
#'
#' @return A nested list where first element is each ref provided, second
#' level each condition to test, and then elements containing information
#' on the comparison. See NetRep::modulePreservation() for more detail.
#'
#' @export

compare_conditions = function(data_expr_list, adja_list, cor_list = NULL,
                              modules_list, ref = names(data_expr_list)[1],
                              test = NULL, cor_func = c("pearson", "spearman",
                                                        "bicor", "other"),
                              your_func = NULL, n_perm = 10000,
                              test_alternative_hyp = c("greater", "less",
                                                       "two.sided"),
                              pvalue_th = 0.01, n_threads = NULL, ...){
  # Basic checks
  if (!is.list(data_expr_list)) stop("data_expr_list must be a list.")
  if (length(data_expr_list) < 2)
    stop("data_expr_list must have at least 2 elements (2 conditions) to run",
         " a comparison.")
  data_expr_list <- lapply(data_expr_list, function(data_expr){
    if (methods::is(data_expr, "SummarizedExperiment")) {
      data_expr <- t(SummarizedExperiment::assay(data_expr))
    } else {
      .check_data_expr(data_expr)
    }
    return(data_expr)
  })
  conditions <- names(data_expr_list)
  if (!is.list(adja_list)) stop("adja_list must be a list.")
  if (!all(conditions %in% names(adja_list)))
    stop("Names in adja_list don't match with conditions.")
  lapply(adja_list, .check_network)
  if (!is.list(cor_list) & !is.null(cor_list))
    stop("cor_list must be a list or NULL")
  if (!is.null(cor_list)) {
    if (!all(conditions %in% names(cor_list)))
      stop("Names in cor_list don't match with conditions.")
    lapply(cor_list, function(cond) {
      if (!is.matrix(cond) & !is.data.frame(cond))
        stop("All correlation tables in cor_list must be either data.frames ",
             "of matrices")
      if (any(!(lapply(cond, is.numeric) %>% unlist)))
        stop("All correlation tables in cor_list must only contain only ",
             "decimal values")
    })
    all_cor <- cor_list %>% unlist # avoid to do a lapply
    if (min(all_cor) < -1 | max(all_cor) > 1)
      stop("Provided correlation_list contains values outside [-1,1].")
  }
  if (!is.character(ref)) stop("ref must be a string or a vector of strings")
  if (all(ref != "cross comparison") & !(all(ref %in% conditions)))
    stop("ref must be a condition name, or a vector of it, matching",
         " conditions.")
  if (length(ref) > 1 & any("cross comparison" %in% ref))
    stop("If multiple ref given, they should be condition names, and none",
         " 'cross comparison'")
  if (!is.null(test) & !is.character(test))
    stop("test must be null, or a string, or a vector of strings")
  if (is.null(test)) { test <- conditions[which(!(conditions %in% ref))]
  } else if (!(all(test %in% conditions))) {
    stop("test must be a condition name, or a vector of it, matching",
         " conditions.") }
  if (!is.list(modules_list))
    stop("modules_list must be a single list of modules or a list by",
         " condition of the modules")
  cor_func <- match.arg(cor_func)
  if (cor_func == "other" & (is.null(your_func) | !is.function(your_func)))
    stop("If you specify other, your_func must be a function.")
  if (!is.numeric(n_perm)) stop("n_perm must be a numeric value")
  if (n_perm %% 1 != 0) stop("n_perm must be a whole number")
  test_alternative_hyp <- match.arg(test_alternative_hyp)
  if (!is.null(n_threads)) {
    if (!is.numeric(n_threads)) stop("n_threads must be a numeric value")
    if (n_threads %% 1 != 0) stop("n_threads must be a whole number")
    if (!is.numeric(n_threads)) stop("n_threads must be a numeric value")
  }
  if (!is.numeric(pvalue_th)) stop("pvalue_th must be a numeric value")
  if (length(pvalue_th) != 1) stop("pvalue_th must be a single value")
  if (pvalue_th <= 0 | pvalue_th >= 1) stop("pvalue_th must be in ]0;1[")

  # Basic checks on modules_list (single cond or multiple cond list ?) +
  # removing conditions into it which are not defined in data_expr_list

  # Looking at conditions cited or not in modules_list
  match_cond_modules_data <- names(modules_list) %in% conditions
  # Meaning it could be a list of modules by condition
  if (any(match_cond_modules_data)) {
    # Removing conditions defined in modules_list but not present in
    # data_expr_list
    if (!all(match_cond_modules_data)) {
      warning("Conditions defined in modules_list not present in",
              " data_expr_list. Removing them.")
      modules_list <- modules_list[which(match_cond_modules_data)]
    }
    lapply(modules_list, function(cond){
      # Checking each cond is a list of modules
      .check_module(cond, is_list = TRUE) })
    is_multi_cond_modules_list = TRUE
  } else { # Meaning it must be a single list of modules
    .check_module(modules_list, is_list = TRUE)
    is_multi_cond_modules_list = FALSE
  }

  # Checks if conditions in ref are defined in modules_list and taking aside
  # conditions defined in modules_list which are not in ref (but still in
  # conditions defined into data_expr_list) for later contingency computing.

  # Checking adequation of content between conditions described in modules
  # and reference choosen
  if (all(ref != "cross comparison")) {
    if (is_multi_cond_modules_list) {
      if (!all(ref %in% names(modules_list)))
        stop("All conditions cited in ref must have their modules described",
             " in modules_list")
      if (!all(names(modules_list) %in% ref)) {
        additional_modules_list <- modules_list[which(
          !(names(modules_list) %in% ref))]
        modules_list <- modules_list[ref]
      }
    } else {
      if (length(ref) > 1)
        stop("modules_list must have at least a list of modules for all",
             " condition cited in ref")
    }
  } else {
    if (!all(conditions %in% names(modules_list))) {
      stop("All conditions must have their modules described in modules_list",
           " when ref is 'cross comparison'")}
  }


  # Process

  # If no cor_list provided, calculating one
  if (is.null(cor_list)) {
    cor_list <- lapply(data_expr_list, function(data_expr){
      if (cor_func == "other") {
        cor_to_use <- your_func
      } else {
        cor_to_use <- .cor_func_match(cor_func)
      }
      cor_mat <- cor_to_use(data_expr %>% as.matrix)
      if (min(cor_mat < -1) | max(cor_mat) > 1)
        stop("Provided correlation function returned values outside [-1,1].")
      return(cor_mat)
    })
  } else { cor_func <- "unknown"}

  # Adapting modules format
  if (is_multi_cond_modules_list) {
    # list by condition of gene named vector of modules values
    modules_reformated <- lapply(modules_list, function(cond){
      lapply(names(cond), function(x){
        stats::setNames(rep(as.numeric(x), length(cond[[x]])), cond[[x]]) }) %>%
        unlist
    })
  } else {
    # Single gene named vector of modules values
    modules_reformated <- lapply(names(modules_list), function(x){
      stats::setNames(rep(as.numeric(x),
                   length(modules_list[[x]])), modules_list[[x]]) }) %>%
      unlist
  }

  if (all(ref == "cross comparison")) {
    test_set <- conditions
    ref_set <- conditions
  } else {
    test_set <- test
    ref_set <- ref
  }

  # Ensuring tables are matrices
  for (table in c("data_expr_list", "cor_list", "adja_list")) {
    assign(table, lapply(get(table), function(cond) {
      if (!is.matrix(cond)) { cond <- as.matrix(cond)
      } else { cond } }))
  }



  # Preservation
  net_rep_preservation <- quiet(NetRep::modulePreservation(
    network = adja_list, data = data_expr_list, correlation = cor_list,
    moduleAssignments = modules_reformated, discovery = ref_set,
    test = test_set, alternative = test_alternative_hyp, nPerm = n_perm,
    nThreads = n_threads, simplify = FALSE, ...))


  # NetRep::modulePreservation doesn't compute contingency matrix when single
  # ref because it force to also have a single moduleAssignement which prevent
  # to compute contingency matrix (and more generaly, it force to have exactly
  # the same conditions in discovery and moduleAssignment. But I want to allow
  # people to pass moduleAssignement for all cond tested even if they're not
  # in discovery, so adding the functionnality
  if (all(ref != "cross comparison") & exists("additional_modules_list")) {
    additional_modules_reformated <- lapply(additional_modules_list,
                                            function(cond){
      lapply(names(cond), function(x){
        stats::setNames(rep(as.numeric(x), length(cond[[x]])), cond[[x]]) }) %>%
                                                unlist
    })
    for (ref_i in ref_set) {
      for (additional_j in names(additional_modules_list)) {
        tmp_module_labels <- list(
          ref_i = modules_reformated[[ref_i]],
          additional_j = additional_modules_reformated[[additional_j]])
        net_rep_preservation[[ref_i]][[additional_j]][["contingency"]] <-
          .contingencyTable(tmp_module_labels,
                           tmp_module_labels$ref_i %>% table %>% names,
                           tmp_module_labels$additional_j %>%
                             names)[["contingency"]]
      }
    }
  }

  # Simplifying final object (yes, modulePreservation has a simplification
  # parameter but I need to get the not simplified version to add
  # contingency matrix correctly)
  prune_list <- function(x) {
    x <- lapply(x, function(y) if (is.list(y)) prune_list(y) else y)
    purrr::compact(x)
  }
  net_rep_preservation <- prune_list(net_rep_preservation)

  # Computing Z summary stat and adding summarising table about module's
  # preservation
  # for (ref_i in names(net_rep_preservation)) {
  #   for (test_j in names(net_rep_preservation[[ref_i]])) {
  preservation_both <- lapply(names(net_rep_preservation), function(ref_i){
    lapply(names(net_rep_preservation[[ref_i]]), function(test_j){

      ij_comparison <- net_rep_preservation[[ref_i]][[test_j]]
      p_values <- ij_comparison$p.values
      z_summary <- z_summary(ij_comparison$observed, ij_comparison$nulls)

      joined_comparison <- lapply(seq_len(nrow(p_values)),
                                  function(module_index){
        module_p_values <- p_values[module_index, ]
        module_z_summary <- z_summary[module_index]

        # Getting comparison output according to NetRep
        get_net_rep_output <- function(bool) {
          if(bool) "preserved" else "not significant"}
        net_rep_res <- switch(
          test_alternative_hyp,
          "greater"  = get_net_rep_output(max(module_p_values) < pvalue_th),
          "less" = get_net_rep_output(min(module_p_values) > 1 - pvalue_th),
          "two.sided" = get_net_rep_output(
            max(module_p_values) < (pvalue_th / 2) |
            min(module_p_values) > 1 - (pvalue_th / 2)),
          stop("Should not be triggered"))

        # Getting comparison output according to Z summary stat
        if (module_z_summary < 2) {
          z_summary_res <- "unpreserved"
        } else if (module_z_summary >= 2 & module_z_summary <= 10) {
          z_summary_res <- "moderately preserved"
        } else if (module_z_summary > 10) {
          z_summary_res <- "preserved"
        } else stop("Should not be triggered")

        # Joining both metrics into a final output
        comparison_single_module <- switch(
          net_rep_res,
         "preserved" = {
           switch(z_summary_res,
                  "preserved" = { "preserved" },
                  "moderately preserved" = { "moderately preserved" },
                  "unpreserved" = { "inconclusive" },
                  stop("Should not be triggered"))},
         "not significant" = {
           switch(z_summary_res,
                  "preserved" = { "inconclusive" },
                  "moderately preserved" = { "moderately preserved" },
                  "unpreserved" = { "unpreserved" },
                  stop("Should not be triggered"))},
         stop("Should not be triggered"))})

      joined_comparison <- joined_comparison %>%
        unlist() %>%
        data.frame(comparison = ., stringsAsFactors = FALSE)

      ij_comparison$z_summary <- z_summary
      ij_comparison$comparison <- joined_comparison

      return(ij_comparison)
    }) %>% setNames(names(net_rep_preservation[[ref_i]]))
  }) %>% setNames(names(net_rep_preservation))

  # Adding metadata about the comparison
  preservation <- list(result = preservation_both,
                       metadata = list(
                         pvalue_th = pvalue_th,
                         cor_func = cor_func,
                         test_alternative_hyp = test_alternative_hyp
                       ))

  return(preservation)
}


# Removing errors about dplyr data-variables
utils::globalVariables(c("module", "statistics", "pvalue"))

#' Heatmap of comparison statistics
#'
#' Plot heatmap of p values for the module comparison statistics evaluated
#' through the permutation test.
#'
#' @param comparison_pvalues matrix or data.frame, table containing the p
#' values for the statistics on each module
#' @param pvalue_th decimal, threshold of pvalue below which statistics are
#' considered as significant
#' @param low_color,pvalue_th_color,unsignificant_color string, color to use
#' as lower, middle, and higher end of the legend. Can either be the color name
#' or hexadecimal code (e.g.: “red” or “#FF1234” )
#' @param text_angle integer, angle in [0,360] of the x axis labels.
#'
#' @importFrom magrittr %>%
#' @importFrom ggplot2 ggplot geom_tile scale_fill_gradientn coord_equal
#' theme_minimal theme aes element_text
#' @importFrom tibble rownames_to_column
#' @importFrom tidyr pivot_longer
#'
#' @return A ggplot object representing a heatmap of the comparison statistics
#' for each module
#'
#' @examples
#' df <- data.frame(avg.weight = abs(rnorm(4, 0.1, 0.1)),
#'                  coherence = abs(rnorm(4, 0.1, 0.1)),
#'                  cor.cor = abs(rnorm(4, 0.1, 0.1)),
#'                  cor.degree = abs(rnorm(4, 0.1, 0.1)),
#'                  cor.contrib = abs(rnorm(4, 0.1, 0.1)),
#'                  avg.cor = abs(rnorm(4, 0.1, 0.1)),
#'                  avg.contrib = abs(rnorm(4, 0.1, 0.1)))
#' plot_comparison_stats(df)
#'
#' @export

plot_comparison_stats <- function(comparison_pvalues, pvalue_th = 0.05,
                                  low_color = "#031643",
                                  pvalue_th_color = "#A0A3D3",
                                  unsignificant_color = "#FFFFFF",
                                  text_angle = 90) {
  # Checks
  if (!is.data.frame(comparison_pvalues) & !is.matrix(comparison_pvalues))
    stop("comparison_pvalues should be a data.frame or a matrix.")
  if (any(!is.numeric(unlist(comparison_pvalues))))
    stop("comparison_pvalues should only contains numeric values")
  if (any(unlist(comparison_pvalues) < 0))
    stop("comparison_pvalues should only contains positive values")
  if (any(unlist(comparison_pvalues) > 1))
    stop("comparison_pvalues should only contains values between 0 and 1")
  if (!is.numeric(pvalue_th)) stop("pvalue_th must be a numeric value")
  if (length(pvalue_th) != 1) stop("pvalue_th must be a single value")
  if (pvalue_th <= 0 | pvalue_th >= 1) stop("pvalue_th must be in ]0;1[")
  lapply(c("low_color", "pvalue_th_color", "unsignificant_color"),
         function(color) {
    var <- get(color)
    if (!is.character(var)) stop(color, " should be a character")
    if (!is.character(var))
      stop(color, " should be a color specified by a name or an hexadecimal",
           " code")
  })
  if (length(text_angle) != 1 | !is.numeric(text_angle))
    stop("text_angle should be a single number")
  if (text_angle < -360 | text_angle > 360)
    stop("text_angle should be a number between -360 and 360")

  df <- comparison_pvalues %>%
    as.data.frame %>%
    tibble::rownames_to_column("module") %>%
    tidyr::pivot_longer(-module, names_to = "statistics", values_to = "pvalue")

  breaks <- c(seq(from = 0, to = pvalue_th, length.out = 4),
              pvalue_th + 0.01, 1) %>% round(digits = 3)

  ggplot2::ggplot(df, ggplot2::aes(statistics, module, fill = pvalue)) +
    ggplot2::geom_tile(color = "white", size = 1) +
    ggplot2::scale_fill_gradientn(colors = c(low_color, pvalue_th_color,
                                             unsignificant_color,
                                             unsignificant_color),
                                  values = c(0, pvalue_th,
                                             pvalue_th + 0.000001, 1),
                                  limits = c(0, 1),
                                  guide = "legend", breaks = breaks) +
    ggplot2::coord_equal() +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = text_angle,
                                                       hjust = 1))
}
