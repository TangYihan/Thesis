# Thesis

Thesis code

The code is stored in the ipynb file type.

The Final (except LSTM) file contains code from data collection, data preprocessing, missing value processing, feature engineering, and LR, SVM, RF, XGBoost, LightGBM, and CNN models, as well as sections used to validate and evaluate the models.
And aki_patients_details.sql is the patient data file for the non-LSTM model, used in the google-big query platform.


The LSTM file includes code ranging from data collection, data preprocessing, missing value processing, feature engineering, and LSTM model related code, as well as a section for validating and evaluating the model.
In the LSTM model, the data used in aki_patients_details.sql is filtered in the ICU patients section and derived from the icu_labevents table in the mimic-iii dataset, creating a new table (direct-plateau-431009-i2.123.lstm_all_icu_ labevents)
