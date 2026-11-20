BEGIN;
INSERT INTO public.demo_shop_customers VALUES
    (101, 'Asha Rao', 'asha@example.test'),
    (102, 'Leo Chen', 'leo@example.test')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.demo_shop_products VALUES
    (201, 'USB-C charger', 25.00),
    (202, 'Travel pouch', 15.00)
ON CONFLICT (id) DO NOTHING;

-- Place orders and record prices at checkout in one transaction.
INSERT INTO public.demo_shop_orders VALUES
    (301, 101, '2025-06-01 10:00+00'),
    (302, 101, '2025-06-01 23:30+00'),
    (303, 102, '2025-06-02 01:15+00')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.demo_shop_order_items (order_id, product_id, quantity, unit_price)
SELECT line.order_id, p.id, line.quantity, p.unit_price
FROM (VALUES (301, 201, 2), (301, 202, 1), (302, 202, 1), (303, 201, 1))
    AS line(order_id, product_id, quantity)
JOIN public.demo_shop_products p ON p.id = line.product_id
ON CONFLICT (order_id, product_id) DO NOTHING;
INSERT INTO public.demo_shop_payments (order_id, amount, status)
SELECT order_id, sum(quantity * unit_price),
       CASE WHEN order_id = 302 THEN 'pending' ELSE 'paid' END
FROM public.demo_shop_order_items
WHERE order_id IN (301, 302, 303)
GROUP BY order_id
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO public.demo_shop_shipments VALUES (301, 'DEMO-TRACK-301', '2025-06-02 09:00+00')
ON CONFLICT (order_id) DO NOTHING;
COMMIT;
