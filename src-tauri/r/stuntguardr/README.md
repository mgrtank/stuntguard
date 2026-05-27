# stuntguardr

`stuntguardr` is the R package used by StuntGuard to train and score a portable stunting-risk model from `Stunting_Dataset.csv`.

## What it does

- cleans and standardizes the stunting dataset
- trains a portable logistic regression model
- balances the training data with simple minority upsampling
- exports the model as JSON for the desktop app
- scores a new child record from JSON input

## Training

Run the training script from the package directory:

```powershell
& 'C:\Program Files\R\R-4.6.0\bin\Rscript.exe' inst/scripts/train_model.R --data="..\..\data\Stunting_Dataset.csv" --output="inst/models/stunting_model.json" --metrics="inst/models/training_metrics.json"
```

## Prediction

The app calls `inst/scripts/predict_patient.R` with a model bundle and a JSON payload.
