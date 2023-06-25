-- 1. What is the total amount each customer spent at the restaurant?
SELECT
    sales.customer_id,
    SUM(menu.price) AS total_sales
FROM dannys_diner.sales
JOIN menu
    ON sales.product_id = menu.product_id
GROUP BY sales.customer_id
ORDER BY sales.customer_id;


-- 2. How many days has each customer visited the restaurant?
SELECT
    customer_id,
    COUNT(DISTINCT(order_date))
FROM dannys_diner.sales
GROUP BY customer_id;


-- 3. What was the first item from the menu purchased by each customer?

-- Inaccurate first solution (it shows only one item, even if more were purchased)
SELECT
    sales.customer_id,
    MIN(sales.order_date),
    menu.product_name
FROM dannys_diner.sales
JOIN menu
    ON sales.product_id = menu.product_id
GROUP BY customer_id;

-- Better solution
WITH ordered_sales AS (
    SELECT 
        sales.customer_id, 
        sales.order_date, 
        menu.product_name,
        DENSE_RANK() OVER(
            PARTITION BY sales.customer_id
            ORDER BY sales.order_date) AS 'rank'
    FROM dannys_diner.sales
    JOIN dannys_diner.menu
        ON sales.product_id = menu.product_id
)
SELECT
    customer_id,
    product_name,
    order_date
FROM ordered_sales
    WHERE `rank` = 1
GROUP BY customer_id, product_name;


-- 4. What is the most purchased item on the menu
-- and how many times was it purchased by all customers?
SELECT
    menu.product_name,
    COUNT(sales.product_id) AS order_count
FROM dannys_diner.sales
JOIN menu
    ON sales.product_id = menu.product_id
GROUP BY menu.product_name
ORDER BY order_count DESC
LIMIT 1;


-- 5. Which item was the most popular for each customer?
WITH customer_favourite AS (
   SELECT
        menu.product_name,
        sales.customer_id,
        COUNT(sales.product_id) AS order_count,
        DENSE_RANK() OVER(
            PARTITION BY sales.customer_id 
            ORDER BY COUNT(sales.customer_id) DESC) AS 'rank'
    FROM dannys_diner.menu
    JOIN dannys_diner.sales
        ON menu.product_id = sales.product_id
    GROUP BY sales.customer_id, menu.product_name
)
SELECT
    customer_id,
    product_name, 
    order_count
FROM customer_favourite
    WHERE `rank` = 1;


-- 6. Which item was purchased first by the customer after they became a member?
WITH purchase_after_member AS (
    SELECT
        members.customer_id, 
        sales.product_id,
        ROW_NUMBER() OVER(
            PARTITION BY members.customer_id
            ORDER BY sales.order_date) AS row_num
    FROM dannys_diner.members
    JOIN dannys_diner.sales
        ON members.customer_id = sales.customer_id
        AND sales.order_date > members.join_date
)
SELECT 
    customer_id,
    menu.product_name
FROM purchase_after_member
JOIN dannys_diner.menu
    ON purchase_after_member.product_id = menu.product_id
WHERE row_num = 1
ORDER BY customer_id ASC;


-- 7. Which item was purchased just before the customer became a member?
WITH purchase_before_member AS (
    SELECT
        members.customer_id, 
        sales.product_id,
        ROW_NUMBER() OVER(
            PARTITION BY members.customer_id
            ORDER BY sales.order_date DESC) AS row_num
    FROM dannys_diner.members
    JOIN dannys_diner.sales
        ON members.customer_id = sales.customer_id
        AND sales.order_date < members.join_date
)
SELECT 
    customer_id,
    menu.product_name
FROM purchase_before_member
JOIN dannys_diner.menu
    ON purchase_before_member.product_id = menu.product_id
WHERE row_num = 1
ORDER BY customer_id ASC;


-- 8. What is the total items and amount spent for each member before they became a member?
-- INNER JOIN because we want only the members, so the members table needs to be considered
-- in the JOIN criteria.
SELECT
    sales.customer_id,
    COUNT(sales.product_id) AS total_items,
    SUM(menu.price) AS total_sales
FROM dannys_diner.sales
INNER JOIN dannys_diner.members
    ON sales.customer_id = members.customer_id
    AND sales.order_date < members.join_date
JOIN dannys_diner.menu
    ON sales.product_id = menu.product_id
GROUP BY sales.customer_id
ORDER BY sales.customer_id;


-- 9. If each $1 spent equates to 10 points and sushi has a 2x points multiplier - 
-- how many points would each customer have?
WITH points_cte AS (
    SELECT
        menu.product_id,
        CASE
            WHEN product_id = 1 THEN price * 20
            ELSE price * 10
        END AS points
    FROM dannys_diner.menu
)
SELECT
    sales.customer_id,
    SUM(points_cte.points) AS total_points
FROM dannys_diner.sales
INNER JOIN points_cte
    ON sales.product_id = points_cte.product_id
GROUP BY sales.customer_id
ORDER BY sales.customer_id;


-- 10. In the first week after a customer joins the program (including their join date)
-- they earn 2x points on all items, not just sushi.
-- - how many points do customer A and B have at the end of January?
WITH dates_cte AS (
    SELECT 
        customer_id,
        join_date,
        join_date + 6 AS valid_date,
        DATE_SUB(DATE_ADD(DATE_FORMAT('2021-01-31', '%Y-%m-01'), INTERVAL 1 MONTH), INTERVAL 1 DAY) AS last_date
    FROM dannys_diner.members
)
SELECT
    sales.customer_id,
    SUM(CASE
            WHEN menu.product_name = 'sushi' THEN 2 * 10 * menu.price
            WHEN sales.order_date BETWEEN dates.join_date AND dates.valid_date THEN 2 * 10 * menu.price
            ELSE 10 * menu.price 
        END) AS points
FROM dannys_diner.sales
INNER JOIN dates_cte AS dates
    ON sales.customer_id = dates.customer_id
    AND sales.order_date <= dates.last_date
INNER JOIN dannys_diner.menu
    ON sales.product_id = menu.product_id
GROUP BY sales.customer_id
ORDER BY sales.customer_id;


-- BONUS QUESTIONS
-- Create a reusable table that joins together information from the different tables.
-- (see depiction on the website)
CREATE VIEW joined_orders_view AS
    SELECT
        sales.customer_id,
        sales.order_date,
        menu.product_name,
        menu.price,
        CASE
            WHEN members.join_date <= sales.order_date THEN 'Y'
            WHEN members.join_date > sales.order_date THEN 'N'
            ELSE 'N'
        END AS member_status
    FROM dannys_diner.sales
    LEFT JOIN dannys_diner.members
        ON sales.customer_id = members.customer_id
    INNER JOIN dannys_diner.menu
        ON sales.product_id = menu.product_id
    ORDER BY sales.customer_id, sales.order_date, menu.product_name;

SELECT * FROM joined_orders_view;


-- Create the same table, but with a product ranking column for members. If the member status
-- is N, then it should contain NULL.
WITH joined_orders_cte AS (
    SELECT
        sales.customer_id,
        sales.order_date,
        menu.product_name,
        menu.price,
        CASE
            WHEN members.join_date <= sales.order_date THEN 'Y'
            WHEN members.join_date > sales.order_date THEN 'N'
            ELSE 'N'
        END AS member_status
    FROM dannys_diner.sales
    LEFT JOIN dannys_diner.members
        ON sales.customer_id = members.customer_id
    INNER JOIN dannys_diner.menu
        ON sales.product_id = menu.product_id
    ORDER BY sales.customer_id, sales.order_date, menu.product_name
)
SELECT
    *,
    CASE
        WHEN member_status = 'N' THEN NULL
        ELSE RANK() OVER (
            PARTITION BY customer_id, member_status
            ORDER BY order_date
            )
    END AS ranking
FROM joined_orders_cte;