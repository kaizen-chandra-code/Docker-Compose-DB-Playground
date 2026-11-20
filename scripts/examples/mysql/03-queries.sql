-- Reorder alert, including items with zero available stock.
SELECT sku, on_hand, reserved, available
FROM demo_stock_inventory
WHERE warehouse_code = 'BLR' AND available <= 5
ORDER BY available, sku;

-- Find an alternate warehouse with enough bags to fulfill a request for 5.
SELECT warehouse_code, available FROM demo_stock_inventory
WHERE sku = 'BAG' AND available >= 5
ORDER BY available DESC, warehouse_code;
