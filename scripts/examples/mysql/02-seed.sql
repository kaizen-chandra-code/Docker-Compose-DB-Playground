START TRANSACTION;
INSERT INTO demo_stock_inventory (warehouse_code, sku, on_hand, reserved)
VALUES ('BLR', 'MUG', 12, 7), ('BLR', 'BAG', 4, 4),
       ('BLR', 'PEN', 30, 0), ('DEL', 'BAG', 18, 2)
ON DUPLICATE KEY UPDATE sku = demo_stock_inventory.sku;
COMMIT;
