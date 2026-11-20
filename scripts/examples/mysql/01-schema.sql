CREATE TABLE IF NOT EXISTS demo_stock_inventory (
    warehouse_code varchar(12),
    sku varchar(16),
    on_hand int NOT NULL CHECK (on_hand >= 0),
    reserved int NOT NULL,
    available int GENERATED ALWAYS AS (on_hand - reserved) STORED,
    CHECK (reserved BETWEEN 0 AND on_hand),
    PRIMARY KEY (warehouse_code, sku),
    INDEX stock_lookup (warehouse_code, available, sku)
) ENGINE=InnoDB;
