BEGIN;
CREATE TABLE IF NOT EXISTS public.demo_shop_customers (
    id integer PRIMARY KEY,
    name text NOT NULL,
    email text NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS public.demo_shop_products (
    id integer PRIMARY KEY,
    name text NOT NULL,
    unit_price numeric(10,2) NOT NULL CHECK (unit_price > 0)
);
CREATE TABLE IF NOT EXISTS public.demo_shop_orders (
    id integer PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES public.demo_shop_customers,
    ordered_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS public.demo_shop_order_items (
    order_id integer REFERENCES public.demo_shop_orders,
    product_id integer REFERENCES public.demo_shop_products,
    quantity integer NOT NULL CHECK (quantity > 0),
    unit_price numeric(10,2) NOT NULL CHECK (unit_price > 0),
    PRIMARY KEY (order_id, product_id)
);
CREATE TABLE IF NOT EXISTS public.demo_shop_payments (
    order_id integer PRIMARY KEY REFERENCES public.demo_shop_orders,
    amount numeric(10,2) NOT NULL CHECK (amount > 0),
    status text NOT NULL CHECK (status IN ('paid', 'pending'))
);
CREATE TABLE IF NOT EXISTS public.demo_shop_shipments (
    order_id integer PRIMARY KEY REFERENCES public.demo_shop_orders,
    tracking_code text NOT NULL UNIQUE,
    shipped_at timestamptz NOT NULL
);
COMMIT;
