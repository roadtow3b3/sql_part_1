<div align="center">
  <img src="https://merklelearn.com/logo-removebg-preview.png" alt="Merklelearn logo" width="260" />
  <h1>SQL Стрим 1</h1>
</div>

## Overview

Этот файл собран как готовый набор запросов с домашкой для стрима: от базовой структуры БД до `JOIN`, `GROUP BY`, `HAVING`, `WINDOW`, `CTE`, `DCL`, `DDL`, `TCL`, функций, триггеров и `EXPLAIN`.

Подписывайся на наш телеграм канал чтобы быть в курсе web3 [ссылка](https://web.telegram.org/a/#-1003862568747) 

Начинай учиться в веб3 уже сейчас [ссылка](https://merklelearn.com)

P.S. у нас есть закрытое сообщество, вход стоит как чашка кофе:

1. 💼 Актуальные вакансии в Web3 более 50 вакансий в день на все позиции, тянем их отовсюду откуда можем
2. 🧑‍🤝‍🧑 Мастермайнды — прокачаешь мышление
3. 🎥 Живые стримы с разбором сложных тем (третья часть всего разбора sql будет доступна только для приватного канала)
4. 🎙️ Реальные записи собеседований — смотри, как проходят офферы
5. 🌐 Платный VPN

Оплата происходит через нашего бота [ссылка](https://web.telegram.org/a/#8671170313)

---

## Structure

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('core','sales','hr','analytics');
```

## FROM

```sql
SELECT *
FROM core.customers
LIMIT 10;

SELECT *
FROM (
    SELECT *
    FROM core.customers
    WHERE first_name LIKE 'Name1%'
) t;
```

## JOIN

```sql
SELECT o.order_id, c.first_name, o.order_status
FROM sales.orders o
JOIN core.customers c ON o.customer_id = c.customer_id
LIMIT 20;

SELECT *
FROM sales.orders
CROSS JOIN core.products
LIMIT 5;

SELECT c.customer_id, o.order_id
FROM core.customers c
LEFT JOIN sales.orders o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL
LIMIT 20;

SELECT c.customer_id, o.order_id
FROM core.customers c
FULL JOIN sales.orders o ON c.customer_id = o.customer_id
LIMIT 20;

SELECT e.employee_id, e.first_name, m.first_name
FROM hr.employees e
LEFT JOIN hr.employees m ON e.manager_id = m.employee_id
LIMIT 20;
```

## WHERE

```sql
SELECT *
FROM sales.orders
WHERE order_status = 'delivered'
LIMIT 20;

SELECT *
FROM sales.orders
WHERE discount_amount > 20;

SELECT customer_id, COUNT(*)
FROM sales.orders
GROUP BY customer_id
HAVING COUNT(*) > 5;

SELECT *
FROM sales.orders o
JOIN core.customers c ON o.customer_id = c.customer_id
WHERE c.country_code = 'UK';

SELECT *
FROM sales.orders o
JOIN core.customers c
  ON o.customer_id = c.customer_id
 AND c.country_code = 'UK';
```

## GROUP BY

```sql
SELECT country_code, COUNT(*)
FROM core.customers
GROUP BY country_code;

SELECT category_id, COUNT(*)
FROM core.products
GROUP BY category_id;

SELECT c.country_code, ci.city_name, COUNT(*)
FROM core.customers c
JOIN core.cities ci ON c.city_id = ci.city_id
GROUP BY c.country_code, ci.city_name;
```

## HAVING

```sql
SELECT country_code, COUNT(*)
FROM core.customers
GROUP BY country_code
HAVING COUNT(*) > 300;

SELECT COUNT(*)
FROM sales.orders
HAVING COUNT(*) > 1000;
```

## SELECT

```sql
SELECT order_id,
       discount_amount,
       discount_amount * 2 AS double_discount
FROM sales.orders
LIMIT 10;
```

## ORDER BY / LIMIT / OFFSET

```sql
SELECT employee_id, salary
FROM hr.employees
ORDER BY salary DESC
LIMIT 10;

SELECT employee_id, salary
FROM hr.employees
ORDER BY salary DESC
LIMIT 5 OFFSET 5;
```

## DDL

```sql
CREATE TABLE analytics.tmp_demo(id INT);

ALTER TABLE analytics.tmp_demo
ADD COLUMN name TEXT;

TRUNCATE TABLE analytics.tmp_demo;

DROP TABLE analytics.tmp_demo;
```

## DML

```sql
INSERT INTO core.categories(category_name)
VALUES ('Demo category');

UPDATE core.products
SET base_price = base_price * 1.01
WHERE product_id < 10;

DELETE FROM sales.returns
WHERE return_id < 5;
```

## DCL

```sql
CREATE ROLE demo_user LOGIN PASSWORD 'demo123';

GRANT SELECT ON ALL TABLES IN SCHEMA core TO demo_user;

REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM demo_user;
```

## TCL

```sql
BEGIN;

UPDATE hr.employees
SET salary = salary * 1.1
WHERE employee_id = 1;

ROLLBACK;
```

## DROP vs TRUNCATE vs DELETE

```sql
DELETE FROM analytics.mv_daily_sales;

TRUNCATE TABLE analytics.mv_daily_sales;
```

## Types: JSON / ARRAY

```sql
SELECT customer_id, profile
FROM core.customers
LIMIT 5;

SELECT customer_id, tags
FROM core.customers
WHERE tags @> ARRAY['vip']::TEXT[];
```

## WINDOW

```sql
SELECT employee_id,
       salary,
       ROW_NUMBER() OVER (ORDER BY salary DESC),
       RANK() OVER (ORDER BY salary DESC)
FROM hr.employees
LIMIT 20;
```

## SUBQUERY

```sql
SELECT *
FROM core.products
WHERE product_id IN (
    SELECT product_id
    FROM sales.order_items
    WHERE quantity >= 3
);
```

## CTE

```sql
WITH t AS (
    SELECT customer_id, COUNT(*) AS cnt
    FROM sales.orders
    GROUP BY customer_id
)
SELECT *
FROM t
WHERE cnt > 5;
```

## VIEW

```sql
SELECT *
FROM analytics.v_order_totals
LIMIT 10;
```

## FUNCTION

```sql
SELECT sales.calculate_order_total(1);

SELECT analytics.customer_ltv(
    (SELECT customer_id FROM core.customers LIMIT 1)
);
```

## TRIGGER

```sql
UPDATE sales.orders
SET order_status = 'shipped'
WHERE order_id = 1;

SELECT *
FROM audit.order_status_log
ORDER BY changed_at DESC
LIMIT 5;
```

## EXPLAIN

```sql
EXPLAIN ANALYZE
SELECT *
FROM sales.orders
WHERE order_status = 'delivered'
ORDER BY order_date DESC
LIMIT 50;
```

---

<div align="center">
  <sub>Prepared for the Merklelearn SQL stream</sub>
</div>
# sql_part_1
