----- AKI defination
---- 肌酐的变化，肌酐在 48 小时内升高至少 0.3 mg/dL 或在 7 天内升高至少 1.5 倍
---- Changes in creatinine, with an increase in creatinine of at least 0.3 mg/dL within 48 hours or at least 1.5-fold within 7 days
WITH baseline_creatinine AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        le.charttime AS baseline_time,
        le.valuenum AS baseline_creat
    FROM
         physionet-data.mimiciii_clinical.labevents le
    INNER JOIN
        physionet-data.mimiciii_clinical.d_labitems dl ON le.itemid = dl.itemid
    WHERE
        dl.label = 'Creatinine'
    GROUP BY
        le.subject_id, le.hadm_id, le.charttime, le.valuenum
),
creatinine_increases AS (
    SELECT
        b.subject_id,
        b.hadm_id,
        le.charttime,
        le.valuenum AS current_creat,
        b.baseline_creat,
        b.baseline_time,
        CASE
          WHEN le.valuenum >= b.baseline_creat + 0.3 AND TIMESTAMP_DIFF(le.charttime, b.baseline_time, HOUR) <= 48 THEN le.charttime
          WHEN le.valuenum >= 1.5 * b.baseline_creat AND TIMESTAMP_DIFF(le.charttime, b.baseline_time, DAY) <= 7 THEN le.charttime
        END AS aki_time
        -- CASE WHEN le.valuenum >= b.baseline_creat + 0.3 AND le.charttime <= b.baseline_time + interval '48 hours' THEN le.CHARTTIME
        --      WHEN le.valuenum >= 1.5 * b.baseline_creat AND le.charttime <= b.baseline_time + interval '7 days' THEN le.CHARTTIME
        -- END AS aki_time
--         case when le.valuenum >= b.baseline_creat + 0.3 AND le.charttime <= b.baseline_time + interval '48 hours' then 0
--              when le.valuenum >= 1.5 * b.baseline_creat AND le.charttime <= b.baseline_time + interval '7 days' then 1
--         end as category  -- drop
    FROM
        baseline_creatinine b
    JOIN
         physionet-data.mimiciii_clinical.labevents le ON b.subject_id = le.subject_id AND b.hadm_id = le.hadm_id
    WHERE
        le.itemid = (SELECT itemid FROM physionet-data.mimiciii_clinical.d_labitems WHERE label = 'Creatinine')
    AND (le.valuenum >= b.baseline_creat + 0.3 AND TIMESTAMP_DIFF(le.charttime, b.baseline_time, HOUR) <= 48
    OR le.valuenum >= 1.5 * b.baseline_creat AND TIMESTAMP_DIFF(le.charttime, b.baseline_time, DAY) <= 7)
),

---- 尿量的判断，连续6h的监测，尿量小于0.5ml/kg/h,此处涉及一个问题是，并不是每个病人都会有连续6h的监测，这个漏斗大概91%。
------ Urine output was determined by 6 h of continuous monitoring with a urine output less than 0.5 ml/kg/h. A problem here is that not every patient will have 6 h of continuous monitoring, and this funnel is about 91%. Judgement of urine output, continuous monitoring for 6h, urine output less than 0.5ml/kg/h, here is a problem that not every patient will have continuous monitoring for 6h, this funnel is about 91%.

Translated with www.DeepL.com/Translator (free version)
urine_output as (
WITH outputevents_with_rownum AS (
  SELECT
    oe.subject_id,
    oe.hadm_id,
    oe.icustay_id,
    oe.charttime,
    oe.value,
    oe.itemid,
    -- icustays.subject_id,
    -- icustays.hadm_id,
    -- icustays.icustay_id,
    ROW_NUMBER() OVER (
      PARTITION BY icustays.subject_id, icustays.hadm_id, icustays.icustay_id
      ORDER BY oe.charttime
    ) AS row_number
  FROM
    `physionet-data.mimiciii_clinical.outputevents` oe
  JOIN
    `physionet-data.mimiciii_clinical.icustays` icustays
  ON
    icustays.subject_id = oe.subject_id
    AND icustays.hadm_id = oe.hadm_id
    AND icustays.icustay_id = oe.icustay_id
  WHERE
    oe.itemid = 40055  -- Assuming urine output itemid is 40055
    AND oe.value IS NOT NULL
)

SELECT
  oe1.subject_id,
  oe1.hadm_id,
  oe1.icustay_id,
  oe1.charttime,
  oe1.value,
  COUNT(oe2.charttime) AS num_records_in_6hr,
  ROUND(SUM(CAST(oe2.value AS FLOAT64)) / 6.0, 3) AS avg_urine_output_6hr
FROM outputevents_with_rownum oe1
JOIN outputevents_with_rownum oe2 ON oe1.subject_id = oe2.subject_id AND oe1.hadm_id = oe2.hadm_id 
    AND oe1.icustay_id = oe2.icustay_id AND ABS(TIMESTAMP_DIFF(oe1.charttime, oe2.charttime, HOUR)) <= 3
GROUP BY
  oe1.subject_id,
  oe1.hadm_id,
  oe1.icustay_id,
  oe1.row_number,
  oe1.charttime,
  oe1.value
ORDER BY
  oe1.subject_id,
  oe1.hadm_id,
  oe1.icustay_id,
  oe1.charttime

    --     SELECT icustays.subject_id,
    --     icustays.hadm_id,
    --     icustays.icustay_id,
    --     outputevents.charttime,
    --     outputevents.value,
    --     COUNT(*) OVER (
    --     PARTITION BY icustays.subject_id, icustays.hadm_id, icustays.icustay_id
    --     ORDER BY outputevents.charttime
    --     RANGE BETWEEN INTERVAL 3 HOUR PRECEDING AND INTERVAL 3 HOUR FOLLOWING
    --   ) AS num_records_in_6hr,
    --   ROUND(
    --     SUM(CAST(outputevents.value AS FLOAT64)) OVER (
    --       PARTITION BY icustays.subject_id, icustays.hadm_id, icustays.icustay_id
    --       ORDER BY outputevents.charttime
    --       RANGE BETWEEN INTERVAL 3 HOUR PRECEDING AND INTERVAL 3 HOUR FOLLOWING
    --     ) / 6.0, 3) AS avg_value_per_6hr
    --     COUNT(outputevents.value) OVER (
    --     PARTITION BY icustays.subject_id, icustays.hadm_id, icustays.icustay_id
    --     ORDER BY outputevents.charttime
    --     RANGE BETWEEN INTERVAL '3 hours' PRECEDING AND INTERVAL '3 hours' FOLLOWING
    --     ) AS num_records_in_6hr,
    --     ROUND( SUM(outputevents.value::numeric) OVER (
    --             PARTITION BY icustays.subject_id, icustays.hadm_id, icustays.icustay_id
    --             ORDER BY outputevents.charttime
    --             RANGE BETWEEN INTERVAL '3 hours' PRECEDING AND INTERVAL '3 hours' FOLLOWING
    --             ) / 6.0, 3
    -- ) AS avg_urine_output_6hr
-- FROM
--     physionet-data.mimiciii_clinical.icustays
--         JOIN
--      physionet-data.mimiciii_clinical.outputevents ON icustays.subject_id = outputevents.subject_id
--         AND icustays.hadm_id = outputevents.hadm_id
--         AND icustays.icustay_id = outputevents.icustay_id
-- WHERE
--     outputevents.itemid = 40055  -- Assuming urine output itemid is 40055
--   AND outputevents.value IS NOT NULL
    ),


---- 诊断aki的时间，肌酐的部分用判断条件成立的时间，尿量的部分用的是满足连续6h且尿量小于等于0.5时的第6小时的时间。
---- The time of diagnosis of aki, creatinine part of the use of the judgement of the time of the establishment of the condition, the part of the amount of urine is used to meet the 6 consecutive h and the amount of urine is less than or equal to 0.5 when the time of the 6th hour.
aki_time as
(
    SELECT
        DISTINCT subject_id
       ,min(aki_time) as aki_time
    FROM
    (SELECT DISTINCT c.subject_id
                       , c.hadm_id
                       , aki_time
         FROM creatinine_increases c
         UNION all
         SELECT DISTINCT u.subject_id
                       , u.hadm_id
                       , case when num_records_in_6hr = 6 then charttime end as aki_time
         FROM urine_output u
         WHERE u.num_records_in_6hr >= 6
           and u.avg_urine_output_6hr <= 0.5)
    GROUP BY
        subject_id),

---  To confirm aki's patient subject_id

aki_patients as (
    SELECT
        DISTINCT c.subject_id
       ,c.hadm_id
    FROM creatinine_increases c

    UNION all

    SELECT
        DISTINCT u.subject_id
       ,u.hadm_id
    FROM urine_output u
    WHERE u.num_records_in_6hr >= 6
    and u.avg_urine_output_6hr <= 0.5 ),

----- the deathtime of patients
death_info AS (
         SELECT
             p.subject_id,
             p.dob,
            --  a.deathtime,
            --  p.dod,
            --  p.dod_hosp,
            --  p.dod_ssn,
             p.gender,
             MAX(COALESCE(a.deathtime, p.dod)) AS final_deathtime,
             MAX(a.admittime) AS last_admittime,
             MAX(a.dischtime) AS last_dischtime
         FROM physionet-data.mimiciii_clinical.patients p
         LEFT JOIN physionet-data.mimiciii_clinical.admissions a ON p.subject_id = a.subject_id
         GROUP BY
             p.subject_id, p.dob, p.gender
         ),
  
--- Patient survival time from diagnosis of aki and age at diagnosis of aki Patient survival time from diagnosis of aki and age at diagnosis of aki

survival_days AS(
 SELECT 
    di.subject_id
   ,CASE WHEN di.final_deathtime IS NOT NULL THEN ROUND(TIMESTAMP_DIFF(di.final_deathtime, ait.aki_time, SECOND) / 86400, 2)
    ELSE NULL END AS survival_days
   ,CASE WHEN TIMESTAMP_DIFF(ait.aki_time, di.dob, DAY) / 365.25 > 89 THEN 90
        ELSE FLOOR(TIMESTAMP_DIFF(ait.aki_time, di.dob, DAY) / 365.25)
    END AS aki_age
 FROM death_info di
 LEFT JOIN aki_time ait ON di.subject_id = ait.subject_id
 GROUP BY 
    di.subject_id
   ,CASE WHEN di.final_deathtime IS NOT NULL THEN ROUND(TIMESTAMP_DIFF(di.final_deathtime, ait.aki_time, SECOND) / 86400, 2)
    ELSE NULL END
   ,CASE WHEN TIMESTAMP_DIFF(ait.aki_time, di.dob, DAY) / 365.25 > 89 THEN 90
        ELSE FLOOR(TIMESTAMP_DIFF(ait.aki_time, di.dob, DAY) / 365.25)
    END
),

---- calculate BMI 

weight_data AS (
    SELECT
        ce.subject_id,
        AVG(ce.valuenum) AS weight_kg
    FROM
        physionet-data.mimiciii_clinical.chartevents ce
    JOIN
        physionet-data.mimiciii_clinical.d_items di ON ce.itemid = di.itemid
    WHERE
        di.label IN ('Admission Weight (kg)', 'Admission Weight', 'Weight (kg)', 'Daily Weight')
        AND ce.valuenum IS NOT NULL
    GROUP BY
        ce.subject_id
),

height_data AS (
    SELECT
        ce.subject_id,
        AVG(ce.valuenum) AS height_cm
    FROM
        physionet-data.mimiciii_clinical.chartevents ce
    JOIN
        physionet-data.mimiciii_clinical.d_items di ON ce.itemid = di.itemid
    WHERE
        di.label IN ('Height (cm)', 'Height')
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0  -- filter out records with zero or negative heights
    GROUP BY
        ce.subject_id
),

bmi_data AS (
    SELECT
        DISTINCT w.subject_id,
        ROUND(w.weight_kg / POWER(h.height_cm / 100, 2), 2) AS bmi
    FROM
        weight_data w
    JOIN
        height_data h ON w.subject_id = h.subject_id
    WHERE
        w.weight_kg IS NOT NULL
        AND h.height_cm IS NOT NULL
)

-----诊断为aki以后的实验室数据的最大值和最小值
-----Maximum and minimum values of laboratory data diagnosed as post-aki Maximum and minimum values of laboratory data diagnosed as post-aki
after_aki_icu_labevents AS (
    SELECT
        ap.subject_id,
        count(distinct ic.icustay_id) as after_aki_icu_num,
        MAX(CASE WHEN di.label = 'Blood Urea Nitrogen' THEN le.valuenum ELSE NULL END) AS after_aki_bun_max,
        MIN(CASE WHEN di.label = 'Blood Urea Nitrogen' THEN le.valuenum ELSE NULL END) AS after_aki_bun_min,
        MAX(CASE WHEN di.label = 'Creatinine' THEN le.valuenum ELSE NULL END) AS after_aki_creatinine_max,
        MIN(CASE WHEN di.label = 'Creatinine' THEN le.valuenum ELSE NULL END) AS after_aki_creatinine_min,
        MAX(CASE WHEN di.label = 'Glucose' THEN le.valuenum ELSE NULL END) AS after_aki_glucose_max,
        MIN(CASE WHEN di.label = 'Glucose' THEN le.valuenum ELSE NULL END) AS after_aki_glucose_min,
        MAX(CASE WHEN di.label = 'Potassium' THEN le.valuenum ELSE NULL END) AS after_aki_potassium_max,
        MIN(CASE WHEN di.label = 'Potassium' THEN le.valuenum ELSE NULL END) AS after_aki_potassium_min,
        MAX(CASE WHEN di.label = 'Calcium' THEN le.valuenum ELSE NULL END) AS after_aki_calcium_max,
        MIN(CASE WHEN di.label = 'Calcium' THEN le.valuenum ELSE NULL END) AS after_aki_calcium_min,
        MAX(CASE WHEN di.label = 'Hemoglobin' THEN le.valuenum ELSE NULL END) AS after_aki_hemoglobin_max,
        MIN(CASE WHEN di.label = 'Hemoglobin' THEN le.valuenum ELSE NULL END) AS after_aki_hemoglobin_min,
        MAX(CASE WHEN di.label = 'Platelet Count' THEN le.valuenum ELSE NULL END) AS after_aki_platelet_max,
        MIN(CASE WHEN di.label = 'Platelet Count' THEN le.valuenum ELSE NULL END) AS after_aki_platelet_min,
        MAX(CASE WHEN di.label = 'White Blood Cell Count' THEN le.valuenum ELSE NULL END) AS after_aki_wbc_max,
        MIN(CASE WHEN di.label = 'White Blood Cell Count' THEN le.valuenum ELSE NULL END) AS after_aki_wbc_min,
        MAX(CASE WHEN di.label = 'Bicarbonate' THEN le.valuenum ELSE NULL END) AS after_aki_bicarbonate_max,
        MIN(CASE WHEN di.label = 'Bicarbonate' THEN le.valuenum ELSE NULL END) AS after_aki_bicarbonate_min,
        MAX(CASE WHEN di.label = 'Oxygen Saturation' THEN ce.valuenum ELSE NULL END) AS after_aki_sp_o2_max,
        MIN(CASE WHEN di.label = 'Oxygen Saturation' THEN ce.valuenum ELSE NULL END) AS after_aki_sp_o2_min,
        MAX(CASE WHEN di.label = 'Urine Output' THEN ce.valuenum ELSE NULL END) AS after_aki_urine_output_max,
        MIN(CASE WHEN di.label = 'Urine Output' THEN ce.valuenum ELSE NULL END) AS after_aki_urine_output_min
    FROM
        aki_patients ap
    JOIN physionet-data.mimiciii_clinical.icustays ic ON ic.subject_id = ap.subject_id
    LEFT JOIN  physionet-data.mimiciii_clinical.labevents le ON ic.hadm_id = le.hadm_id
    LEFT JOIN physionet-data.mimiciii_clinical.d_labitems di ON le.itemid = di.itemid
    LEFT JOIN physionet-data.mimiciii_clinical.chartevents ce ON ic.icustay_id = ce.icustay_id
    LEFT JOIN aki_time ait ON le.subject_id = ait.subject_id
    WHERE le.charttime >= ait.aki_time AND ic.icustay_id is not null
      AND di.label in ('Blood Urea Nitrogen','Creatinine','Glucose','Potassium','Calcium','Platelet Count','White Blood Cell Count'
    'Bicarbonate','Oxygen Saturation')
    GROUP BY 
      ap.subject_id
),

-----入院icu后24小时内的实验室数据的最大值和最小值
---Maximum and minimum values of laboratory data within 24 hours of admission to the ICU

icu_labevents AS (
    SELECT
        ap.subject_id,
        count(distinct ic.icustay_id) as icu_num,
        MAX(CASE WHEN di.label = 'Blood Urea Nitrogen' THEN le.valuenum ELSE NULL END) AS bun_max,
        MIN(CASE WHEN di.label = 'Blood Urea Nitrogen' THEN le.valuenum ELSE NULL END) AS bun_min,
        MAX(CASE WHEN di.label = 'Creatinine' THEN le.valuenum ELSE NULL END) AS creatinine_max,
        MIN(CASE WHEN di.label = 'Creatinine' THEN le.valuenum ELSE NULL END) AS creatinine_min,
        MAX(CASE WHEN di.label = 'Glucose' THEN le.valuenum ELSE NULL END) AS glucose_max,
        MIN(CASE WHEN di.label = 'Glucose' THEN le.valuenum ELSE NULL END) AS glucose_min,
        MAX(CASE WHEN di.label = 'Potassium' THEN le.valuenum ELSE NULL END) AS potassium_max,
        MIN(CASE WHEN di.label = 'Potassium' THEN le.valuenum ELSE NULL END) AS potassium_min,
        MAX(CASE WHEN di.label = 'Calcium' THEN le.valuenum ELSE NULL END) AS calcium_max,
        MIN(CASE WHEN di.label = 'Calcium' THEN le.valuenum ELSE NULL END) AS calcium_min,
        MAX(CASE WHEN di.label = 'Hemoglobin' THEN le.valuenum ELSE NULL END) AS hemoglobin_max,
        MIN(CASE WHEN di.label = 'Hemoglobin' THEN le.valuenum ELSE NULL END) AS hemoglobin_min,
        MAX(CASE WHEN di.label = 'Platelet Count' THEN le.valuenum ELSE NULL END) AS platelet_max,
        MIN(CASE WHEN di.label = 'Platelet Count' THEN le.valuenum ELSE NULL END) AS platelet_min,
        MAX(CASE WHEN di.label = 'White Blood Cell Count' THEN le.valuenum ELSE NULL END) AS wbc_max,
        MIN(CASE WHEN di.label = 'White Blood Cell Count' THEN le.valuenum ELSE NULL END) AS wbc_min,
        MAX(CASE WHEN di.label = 'Bicarbonate' THEN le.valuenum ELSE NULL END) AS bicarbonate_max,
        MIN(CASE WHEN di.label = 'Bicarbonate' THEN le.valuenum ELSE NULL END) AS bicarbonate_min,
        MAX(CASE WHEN di.label = 'Oxygen Saturation' THEN ce.valuenum ELSE NULL END) AS sp_o2_max,
        MIN(CASE WHEN di.label = 'Oxygen Saturation' THEN ce.valuenum ELSE NULL END) AS sp_o2_min,
        MAX(CASE WHEN di.label = 'Urine Output' THEN ce.valuenum ELSE NULL END) AS urine_output_max,
        MIN(CASE WHEN di.label = 'Urine Output' THEN ce.valuenum ELSE NULL END) AS urine_output_min
    FROM
        aki_patients ap
    JOIN physionet-data.mimiciii_clinical.icustays ic ON ic.subject_id = ap.subject_id
    LEFT JOIN  physionet-data.mimiciii_clinical.labevents le ON ic.hadm_id = le.hadm_id
    LEFT JOIN physionet-data.mimiciii_clinical.d_labitems di ON le.itemid = di.itemid
    LEFT JOIN physionet-data.mimiciii_clinical.chartevents ce ON ic.icustay_id = ce.icustay_id
    LEFT JOIN aki_time ait ON le.subject_id = ait.subject_id
    WHERE (le.charttime BETWEEN ic.intime AND ic.intime + INTERVAL '24' HOUR
         OR ce.charttime BETWEEN ic.intime AND ic.intime + INTERVAL '24' HOUR) AND ic.icustay_id is not null
      AND di.label in ('Blood Urea Nitrogen','Creatinine','Glucose','Potassium','Calcium','Platelet Count','White Blood Cell Count'
    'Bicarbonate','Oxygen Saturation')
    GROUP BY 
      ap.subject_id
)



select 
  a.subject_id
 ,b.aki_time as confirm_aki_time
 ,CASE WHEN c.gender = 'F' THEN 0 
       WHEN c.gender = 'M' THEN 1
  ELSE null end as gender -- 0 is female、1 male
 ,c.final_deathtime as final_deathtime
 ,d.survival_days
 ,d.aki_age
 ,e.bmi
 ,f.after_aki_icu_num,
  f.after_aki_bun_max,
  f.after_aki_bun_min,
  f.after_aki_creatinine_max,
  f.after_aki_creatinine_min,
  f.after_aki_glucose_max,
  f.after_aki_glucose_min,
  f.after_aki_potassium_max,
  f.after_aki_potassium_min,
  f.after_aki_calcium_max,
  f.after_aki_calcium_min,
  f.after_aki_hemoglobin_max,
  f.after_aki_hemoglobin_min,
  f.after_aki_platelet_max,
  f.after_aki_platelet_min,
  f.after_aki_wbc_max,
  f.after_aki_wbc_min,
  f.after_aki_bicarbonate_max,
  f.after_aki_bicarbonate_min,
  f.after_aki_sp_o2_max,
  f.after_aki_sp_o2_min,
  f.after_aki_urine_output_max,
  f.after_aki_urine_output_min
 ,g.icu_num,
  g.bun_max,
  g.bun_min,
  g.creatinine_max,
  g.creatinine_min,
  g.glucose_max,
  g.glucose_min,
  g.potassium_max,
  g.potassium_min,
  g.calcium_max,
  g.calcium_min,
  g.hemoglobin_max,
  g.hemoglobin_min,
  g.platelet_max,
  g.platelet_min,
  g.wbc_max,
  g.wbc_min,
  g.bicarbonate_max,
  g.bicarbonate_min,
  g.sp_o2_max,
  g.sp_o2_min,
  g.urine_output_max,
  g.urine_output_min
from aki_patients a
left join aki_time b on a.subject_id = b.subject_id
left join death_info c on a.subject_id = c.subject_id
left join survival_days d on a.subject_id = d.subject_id
left join bmi_data e on a.subject_id = e.subject_id
-- left join after_aki_icu_labevents f on a.subject_id = f.subject_id
-- left join icu_labevents g on a.subject_id = g.subject_id
GROUP BY 
  a.subject_id
 ,b.aki_time
 ,CASE WHEN c.gender = 'F' THEN 0 
       WHEN c.gender = 'M' THEN 1
  ELSE null end
 ,c.final_deathtime
 ,d.survival_days
 ,d.aki_age
 ,e.bmi
 ,f.after_aki_icu_num,
  f.after_aki_bun_max,
  f.after_aki_bun_min,
  f.after_aki_creatinine_max,
  f.after_aki_creatinine_min,
  f.after_aki_glucose_max,
  f.after_aki_glucose_min,
  f.after_aki_potassium_max,
  f.after_aki_potassium_min,
  f.after_aki_calcium_max,
  f.after_aki_calcium_min,
  f.after_aki_hemoglobin_max,
  f.after_aki_hemoglobin_min,
  f.after_aki_platelet_max,
  f.after_aki_platelet_min,
  f.after_aki_wbc_max,
  f.after_aki_wbc_min,
  f.after_aki_bicarbonate_max,
  f.after_aki_bicarbonate_min,
  f.after_aki_sp_o2_max,
  f.after_aki_sp_o2_min,
  f.after_aki_urine_output_max,
  f.after_aki_urine_output_min
 ,g.icu_num,
  g.bun_max,
  g.bun_min,
  g.creatinine_max,
  g.creatinine_min,
  g.glucose_max,
  g.glucose_min,
  g.potassium_max,
  g.potassium_min,
  g.calcium_max,
  g.calcium_min,
  g.hemoglobin_max,
  g.hemoglobin_min,
  g.platelet_max,
  g.platelet_min,
  g.wbc_max,
  g.wbc_min,
  g.bicarbonate_max,
  g.bicarbonate_min,
  g.sp_o2_max,
  g.sp_o2_min,
  g.urine_output_max,
  g.urine_output_min

