-- Olist Brazilian E-commerce: SQL + Tableau project
-- Business question: does late delivery hurt review scores, and which
-- categories/sellers are driving the delays?
--
-- Column note: this DB was imported without header detection, so columns
-- show up as field1, field2, etc. in Execute SQL. Rename/re-import with
-- "Column names in first line" checked to clean this up before publishing.
-- Real column names are noted in comments below for reference.
 
-- =========================================================
-- Step 1: Delivery delay per order (in days)
-- field7 = order_delivered_customer_date
-- field8 = order_estimated_delivery_date
-- Positive = delivered late, negative = delivered early.
-- =========================================================
SELECT
    field1,
    ROUND(julianday(field7) - julianday(field8), 2) AS Delay_Days
FROM olist_orders_dataset
WHERE field7 IS NOT NULL;
 
 
-- =========================================================
-- Step 2: Pair delay with review score.
-- olist_order_reviews_dataset can have more than one review row per
-- order_id (confirmed: 96,360 review rows vs 95,831 distinct orders),
-- so review_score is averaged per order to avoid double-counting orders
-- with multiple review records.
-- field2 (reviews) = order_id, field3 (reviews) = review_score
-- =========================================================
SELECT
    olist_orders_dataset.field1,
    ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) AS Days,
    AVG(olist_order_reviews_dataset.field3) AS Avg_Score
FROM olist_orders_dataset
JOIN olist_order_reviews_dataset
    ON olist_orders_dataset.field1 = olist_order_reviews_dataset.field2
WHERE olist_orders_dataset.field7 IS NOT NULL
GROUP BY olist_orders_dataset.field1;
 
 
-- =========================================================
-- Step 3: Bucket each order's delay into a category.
-- =========================================================
SELECT
    olist_orders_dataset.field1,
    ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) AS Days,
    AVG(olist_order_reviews_dataset.field3) AS Avg_Score,
    CASE
        WHEN ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) <= 0 THEN 'Early/On Time'
        WHEN ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) BETWEEN 1 AND 3 THEN '1-3 Days Late'
        WHEN ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) BETWEEN 4 AND 7 THEN '4-7 Days Late'
        WHEN ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) >= 8 THEN '8+ Days Late'
        ELSE 'Not Delivered'
    END AS Days_Late
FROM olist_orders_dataset
JOIN olist_order_reviews_dataset
    ON olist_orders_dataset.field1 = olist_order_reviews_dataset.field2
WHERE olist_orders_dataset.field7 IS NOT NULL
GROUP BY olist_orders_dataset.field1;
 
 
-- =========================================================
-- Step 4: Average review score and order count per delay bucket.
-- This is the headline finding: review scores drop in a clean, monotonic
-- pattern as delay increases. "Not Delivered" is a separate case (orders
-- with no delivery date logged, likely cancelled/lost) and shouldn't be
-- read as part of the delay trend.
--
-- Result:
-- Early/On Time    88174 orders   4.29 avg score
-- 1-3 Days Late     1363 orders   3.51 avg score
-- 4-7 Days Late     1284 orders   2.18 avg score
-- 8+ Days Late      2786 orders   1.70 avg score
-- Not Delivered     2224 orders   3.29 avg score (separate category, not on the delay trend)
-- =========================================================
SELECT
    Days_Late,
    COUNT(*) AS Order_Count,
    ROUND(AVG(Avg_Score), 2) AS Overall_Avg_Score
FROM (
    SELECT
        olist_orders_dataset.field1,
        ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) AS Days,
        AVG(olist_order_reviews_dataset.field3) AS Avg_Score,
        CASE
            WHEN ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) <= 0 THEN 'Early/On Time'
            WHEN ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) BETWEEN 1 AND 3 THEN '1-3 Days Late'
            WHEN ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) BETWEEN 4 AND 7 THEN '4-7 Days Late'
            WHEN ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) >= 8 THEN '8+ Days Late'
            ELSE 'Not Delivered'
        END AS Days_Late
    FROM olist_orders_dataset
    JOIN olist_order_reviews_dataset
        ON olist_orders_dataset.field1 = olist_order_reviews_dataset.field2
    WHERE olist_orders_dataset.field7 IS NOT NULL
    GROUP BY olist_orders_dataset.field1
) AS delay_data
GROUP BY Days_Late;
 
 
-- =========================================================
-- Step 5: Investigate the "Not Delivered" bucket (field7 IS NULL).
-- Question raised: could this be in-store pickups? No -- Olist is an
-- online-only marketplace, no physical stores. Checked order_status
-- (field3) for these rows instead of guessing.
-- =========================================================
SELECT DISTINCT field3, field7
FROM olist_orders_dataset
WHERE field7 IS NULL;
-- Result: invoiced, shipped, processing, unavailable, canceled,
-- delivered, created, approved -- all statuses where the order simply
-- never completed/logged a delivery, not a pickup scenario.
 
-- Data-quality note: 8 orders have status = 'delivered' but no logged
-- delivery date -- a small logging gap, not material to the analysis.
SELECT COUNT(field3)
FROM olist_orders_dataset
WHERE field3 IS 'delivered' AND field7 IS NULL;
-- Result: 8
 
 
-- =========================================================
-- Step 6: Which categories are driving delays?
-- olist_order_items_dataset: field1=order_id, field3=product_id, field4=seller_id
-- Joins orders -> order_items -> products. One row per order-item
-- (repeats expected: multi-item orders show up once per item).
-- Late_Rate uses conditional aggregation (SUM of a CASE flag) cast to
-- REAL to avoid SQLite's integer division truncating everything to 0/1.
-- Item_Count matters as much as Late_Rate -- a high rate on a handful
-- of items isn't a real signal (e.g. pc_gamer: 0% late, but only 8 items).
-- =========================================================
SELECT Category, AVG(Days) as Average_Days,
    CAST(SUM(CASE WHEN Days > 0 THEN 1 ELSE 0 END) AS REAL) / COUNT(*) AS Late_Rate,
    COUNT(*) AS Item_Count
FROM (
    SELECT olist_orders_dataset.field1 as Order_ID,
        ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) AS Days,
        olist_products_dataset.field2 as Category
    FROM olist_orders_dataset
    JOIN olist_order_items_dataset
        ON olist_orders_dataset.field1 = olist_order_items_dataset.field1
    JOIN olist_products_dataset
        ON olist_order_items_dataset.field3 = olist_products_dataset.field1
    WHERE olist_orders_dataset.field7 IS NOT NULL
) as Delay_Data
GROUP BY Category
ORDER BY Late_Rate DESC;
 
 
-- =========================================================
-- Step 7: Which sellers are driving delays?
-- Same pattern as Step 6, but seller_id lives directly in order_items --
-- no need to join to products at all for this version.
-- =========================================================
SELECT Seller_id, AVG(Days) as Average_Days,
    CAST(SUM(CASE WHEN Days > 0 THEN 1 ELSE 0 END) AS REAL) / COUNT(*) AS Late_Rate,
    COUNT(*) AS Item_Count
FROM (
    SELECT olist_orders_dataset.field1 as Order_ID,
        ROUND(julianday(olist_orders_dataset.field7) - julianday(olist_orders_dataset.field8), 2) AS Days,
        olist_order_items_dataset.field4 as Seller_id
    FROM olist_orders_dataset
    JOIN olist_order_items_dataset
        ON olist_orders_dataset.field1 = olist_order_items_dataset.field1
    WHERE olist_orders_dataset.field7 IS NOT NULL
) as Delay_Data
GROUP BY Seller_id
ORDER BY Late_Rate DESC;
 
 
-- =========================================================
-- Step 8: Data-quality checks on the category breakdown.
-- =========================================================
 
-- casa_conforto vs casa_conforto_2: near-duplicate category names.
SELECT field2, COUNT(*) AS product_count
FROM olist_products_dataset
WHERE field2 LIKE 'casa_conforto%'
GROUP BY field2;
-- Result: casa_conforto = 111 products, casa_conforto_2 = 5 products.
-- casa_conforto_2 is a data-entry duplicate/mislabel, not a real distinct
-- category -- noted, not merged, in the analysis above.
 
-- Order_items with no matching category (product_id didn't join to a
-- category, or the category is blank).
SELECT COUNT(*)
FROM olist_order_items_dataset
LEFT JOIN olist_products_dataset
    ON olist_order_items_dataset.field3 = olist_products_dataset.field1
WHERE olist_products_dataset.field2 IS NULL;
-- Result: 1,603 of ~110,197 order_items (~1.5%) -- small gap, excluded
-- from category-level analysis, doesn't change conclusions.
-- =========================================================
 
