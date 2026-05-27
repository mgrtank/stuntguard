stg_evaluate_predictions <- function(truth, probability, positive_label = 1) {
  truth <- as.integer(as.vector(truth) == positive_label)
  probability <- as.numeric(as.vector(probability))

  if (length(truth) != length(probability)) {
    stop(sprintf("Truth and probability lengths differ (%s vs %s)", length(truth), length(probability)))
  }

  prediction <- ifelse(probability >= 0.5, 1, 0)

  tp <- sum(prediction == 1 & truth == 1)
  tn <- sum(prediction == 0 & truth == 0)
  fp <- sum(prediction == 1 & truth == 0)
  fn <- sum(prediction == 0 & truth == 1)

  accuracy <- (tp + tn) / length(truth)
  precision <- if ((tp + fp) == 0) 0 else tp / (tp + fp)
  recall <- if ((tp + fn) == 0) 0 else tp / (tp + fn)
  f1 <- if ((precision + recall) == 0) 0 else 2 * precision * recall / (precision + recall)

  list(
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    f1 = f1,
    confusion = list(tp = tp, tn = tn, fp = fp, fn = fn)
  )
}
