-- 
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET_ID}.monthly_comp_data` AS
WITH daily_data AS (
  SELECT
    EXTRACT(MONTH FROM date) AS month,
    EXTRACT(YEAR FROM date) AS year,
    temp_max,
    temp_min,
    (temp_max + temp_min) / 2 AS avg_temp,
    humidity_mean,
    -- 不快指数の計算（1日単位）
    (0.81 * ((temp_max + temp_min) / 2) + 0.01 * humidity_mean * (0.99 * ((temp_max + temp_min) / 2) - 14.3) + 46.3) AS di
  FROM `{PROJECT_ID}.{DATASET_ID}.raw_weather_data`
)
SELECT
  month,
  -- 70年前 (1952-1954) の集計
  ROUND(AVG(IF(year BETWEEN 1952 AND 1954, avg_temp, NULL)), 1) AS avg_temp_70s,
  ROUND(AVG(IF(year BETWEEN 1952 AND 1954, temp_max, NULL)), 1) AS temp_max_70s,
  ROUND(AVG(IF(year BETWEEN 1952 AND 1954, humidity_mean, NULL)), 1) AS humidity_70s,
  ROUND(AVG(IF(year BETWEEN 1952 AND 1954, di, NULL)), 1) AS di_70s,
  
  -- 現代 (2023-2025) の集計
  ROUND(AVG(IF(year BETWEEN 2023 AND 2025, avg_temp, NULL)), 1) AS avg_temp_now,
  ROUND(AVG(IF(year BETWEEN 2023 AND 2025, temp_max, NULL)), 1) AS temp_max_now,
  ROUND(AVG(IF(year BETWEEN 2023 AND 2025, humidity_mean, NULL)), 1) AS humidity_now,
  ROUND(AVG(IF(year BETWEEN 2023 AND 2025, di, NULL)), 1) AS di_now
FROM daily_data
GROUP BY month
ORDER BY month;
