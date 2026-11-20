-- Order history for Asha, including the pending order without a shipment.
WITH order_totals AS (
    SELECT order_id, sum(quantity * unit_price) AS order_total
    FROM public.demo_shop_order_items GROUP BY order_id
)
SELECT c.name, o.id, totals.order_total, p.status, s.tracking_code
FROM public.demo_shop_customers c
JOIN public.demo_shop_orders o ON o.customer_id = c.id
JOIN order_totals totals ON totals.order_id = o.id
JOIN public.demo_shop_payments p ON p.order_id = o.id
LEFT JOIN public.demo_shop_shipments s ON s.order_id = o.id
WHERE c.id = 101
ORDER BY o.ordered_at DESC;

-- Paid order revenue by UTC order date.
SELECT (o.ordered_at AT TIME ZONE 'UTC')::date AS order_day,
       count(*) AS paid_orders, sum(p.amount) AS revenue
FROM public.demo_shop_orders o
JOIN public.demo_shop_payments p ON p.order_id = o.id
WHERE p.status = 'paid'
GROUP BY order_day ORDER BY order_day;
