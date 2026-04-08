BEGIN;

-- -----------------------------
-- 0. Extensions
-- -----------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- -----------------------------
-- 1. Schemas
-- -----------------------------
DROP SCHEMA IF EXISTS core CASCADE;
DROP SCHEMA IF EXISTS sales CASCADE;
DROP SCHEMA IF EXISTS hr CASCADE;
DROP SCHEMA IF EXISTS analytics CASCADE;
DROP SCHEMA IF EXISTS audit CASCADE;

CREATE SCHEMA core;
CREATE SCHEMA sales;
CREATE SCHEMA hr;
CREATE SCHEMA analytics;
CREATE SCHEMA audit;

-- -----------------------------
-- 2. Custom types / domains
-- -----------------------------
CREATE DOMAIN core.email_address AS CITEXT
CHECK (VALUE ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$');

CREATE TYPE core.order_status AS ENUM (
    'new',
    'paid',
    'packed',
    'shipped',
    'delivered',
    'cancelled',
    'refunded'
);

CREATE TYPE core.payment_method AS ENUM (
    'card',
    'cash',
    'bank_transfer',
    'paypal',
    'apple_pay'
);

CREATE TYPE hr.employment_status AS ENUM (
    'probation',
    'active',
    'vacation',
    'terminated'
);

-- -----------------------------
-- 3. Sequences
-- -----------------------------
CREATE SEQUENCE core.customer_code_seq START 1000;
CREATE SEQUENCE sales.invoice_number_seq START 50000;

-- -----------------------------
-- 4. Core reference tables
-- -----------------------------
CREATE TABLE core.countries (
    country_code CHAR(2) PRIMARY KEY,
    country_name TEXT NOT NULL UNIQUE,
    region TEXT NOT NULL
);

CREATE TABLE core.cities (
    city_id BIGSERIAL PRIMARY KEY,
    country_code CHAR(2) NOT NULL REFERENCES core.countries(country_code),
    city_name TEXT NOT NULL,
    timezone_name TEXT NOT NULL,
    population INTEGER CHECK (population >= 0),
    UNIQUE (country_code, city_name)
);

CREATE TABLE core.customers (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_code TEXT NOT NULL UNIQUE DEFAULT ('CUST-' || nextval('core.customer_code_seq')),
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email core.email_address NOT NULL UNIQUE,
    phone TEXT,
    birth_date DATE,
    country_code CHAR(2) NOT NULL REFERENCES core.countries(country_code),
    city_id BIGINT REFERENCES core.cities(city_id),
    loyalty_points INTEGER NOT NULL DEFAULT 0 CHECK (loyalty_points >= 0),
    tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    profile JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE core.addresses (
    address_id BIGSERIAL PRIMARY KEY,
    customer_id UUID NOT NULL REFERENCES core.customers(customer_id) ON DELETE CASCADE,
    address_type VARCHAR(20) NOT NULL CHECK (address_type IN ('home', 'work', 'shipping', 'billing')),
    line1 TEXT NOT NULL,
    line2 TEXT,
    postal_code TEXT,
    city_id BIGINT NOT NULL REFERENCES core.cities(city_id),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE core.categories (
    category_id BIGSERIAL PRIMARY KEY,
    category_name TEXT NOT NULL UNIQUE,
    parent_category_id BIGINT REFERENCES core.categories(category_id)
);

CREATE TABLE core.products (
    product_id BIGSERIAL PRIMARY KEY,
    sku TEXT NOT NULL UNIQUE,
    product_name TEXT NOT NULL,
    category_id BIGINT NOT NULL REFERENCES core.categories(category_id),
    brand TEXT NOT NULL,
    base_price NUMERIC(12,2) NOT NULL CHECK (base_price >= 0),
    weight_kg NUMERIC(8,3) CHECK (weight_kg >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    attributes JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE core.product_prices (
    product_price_id BIGSERIAL PRIMARY KEY,
    product_id BIGINT NOT NULL REFERENCES core.products(product_id) ON DELETE CASCADE,
    valid_from DATE NOT NULL,
    valid_to DATE,
    price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'USD',
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE core.warehouses (
    warehouse_id BIGSERIAL PRIMARY KEY,
    warehouse_name TEXT NOT NULL UNIQUE,
    city_id BIGINT NOT NULL REFERENCES core.cities(city_id),
    capacity INTEGER NOT NULL CHECK (capacity > 0),
    meta JSONB NOT NULL DEFAULT '{}'::JSONB
);

CREATE TABLE core.inventory (
    warehouse_id BIGINT NOT NULL REFERENCES core.warehouses(warehouse_id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES core.products(product_id) ON DELETE CASCADE,
    quantity_on_hand INTEGER NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    reorder_level INTEGER NOT NULL DEFAULT 10 CHECK (reorder_level >= 0),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (warehouse_id, product_id)
);

-- -----------------------------
-- 5. HR tables
-- -----------------------------
CREATE TABLE hr.departments (
    department_id BIGSERIAL PRIMARY KEY,
    department_name TEXT NOT NULL UNIQUE,
    budget NUMERIC(14,2) NOT NULL CHECK (budget >= 0)
);

CREATE TABLE hr.employees (
    employee_id BIGSERIAL PRIMARY KEY,
    manager_id BIGINT REFERENCES hr.employees(employee_id),
    department_id BIGINT NOT NULL REFERENCES hr.departments(department_id),
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email core.email_address NOT NULL UNIQUE,
    hire_date DATE NOT NULL,
    status hr.employment_status NOT NULL DEFAULT 'active',
    salary NUMERIC(12,2) NOT NULL CHECK (salary > 0),
    bonus_pct NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (bonus_pct >= 0 AND bonus_pct <= 100),
    skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    employee_meta JSONB NOT NULL DEFAULT '{}'::JSONB
);

CREATE TABLE hr.employee_salaries (
    salary_id BIGSERIAL PRIMARY KEY,
    employee_id BIGINT NOT NULL REFERENCES hr.employees(employee_id) ON DELETE CASCADE,
    effective_from DATE NOT NULL,
    salary NUMERIC(12,2) NOT NULL CHECK (salary > 0),
    reason TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- -----------------------------
-- 6. Sales tables
-- -----------------------------
CREATE TABLE sales.orders (
    order_id BIGSERIAL PRIMARY KEY,
    customer_id UUID NOT NULL REFERENCES core.customers(customer_id),
    shipping_address_id BIGINT REFERENCES core.addresses(address_id),
    order_status core.order_status NOT NULL DEFAULT 'new',
    payment_method core.payment_method,
    invoice_number TEXT NOT NULL UNIQUE DEFAULT ('INV-' || nextval('sales.invoice_number_seq')),
    order_date TIMESTAMP NOT NULL DEFAULT NOW(),
    required_date DATE,
    shipped_date TIMESTAMP,
    discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    shipping_fee NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (shipping_fee >= 0),
    notes TEXT,
    source_channel TEXT NOT NULL DEFAULT 'web',
    extra_data JSONB NOT NULL DEFAULT '{}'::JSONB
);

CREATE TABLE sales.order_items (
    order_item_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES sales.orders(order_id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES core.products(product_id),
    warehouse_id BIGINT REFERENCES core.warehouses(warehouse_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    line_discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (line_discount >= 0),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (order_id, product_id, warehouse_id)
);

CREATE TABLE sales.payments (
    payment_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES sales.orders(order_id) ON DELETE CASCADE,
    payment_date TIMESTAMP NOT NULL DEFAULT NOW(),
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    method core.payment_method NOT NULL,
    transaction_id UUID NOT NULL DEFAULT gen_random_uuid(),
    is_successful BOOLEAN NOT NULL DEFAULT TRUE,
    response_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
    UNIQUE (transaction_id)
);

CREATE TABLE sales.shipments (
    shipment_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES sales.orders(order_id) ON DELETE CASCADE,
    warehouse_id BIGINT NOT NULL REFERENCES core.warehouses(warehouse_id),
    shipped_at TIMESTAMP,
    delivered_at TIMESTAMP,
    carrier TEXT,
    tracking_number TEXT UNIQUE,
    shipping_cost NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (shipping_cost >= 0),
    status TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'in_transit', 'delivered', 'lost', 'returned'))
);

CREATE TABLE sales.returns (
    return_id BIGSERIAL PRIMARY KEY,
    order_item_id BIGINT NOT NULL REFERENCES sales.order_items(order_item_id) ON DELETE CASCADE,
    return_date TIMESTAMP NOT NULL DEFAULT NOW(),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    reason TEXT NOT NULL,
    refund_amount NUMERIC(12,2) NOT NULL CHECK (refund_amount >= 0)
);

-- -----------------------------
-- 7. Audit tables
-- -----------------------------
CREATE TABLE audit.order_status_log (
    log_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    old_status core.order_status,
    new_status core.order_status NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    changed_by TEXT NOT NULL DEFAULT CURRENT_USER
);

CREATE TABLE audit.customer_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    customer_id UUID NOT NULL,
    action_type TEXT NOT NULL,
    old_row JSONB,
    new_row JSONB,
    changed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    changed_by TEXT NOT NULL DEFAULT CURRENT_USER
);

-- -----------------------------
-- 8. Utility functions
-- -----------------------------
CREATE OR REPLACE FUNCTION core.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit.log_order_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.order_status IS DISTINCT FROM NEW.order_status THEN
        INSERT INTO audit.order_status_log(order_id, old_status, new_status)
        VALUES (NEW.order_id, OLD.order_status, NEW.order_status);
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION audit.log_customer_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit.customer_audit(customer_id, action_type, new_row)
        VALUES (NEW.customer_id, 'INSERT', to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit.customer_audit(customer_id, action_type, old_row, new_row)
        VALUES (NEW.customer_id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit.customer_audit(customer_id, action_type, old_row)
        VALUES (OLD.customer_id, 'DELETE', to_jsonb(OLD));
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION sales.calculate_order_total(p_order_id BIGINT)
RETURNS NUMERIC(14,2)
LANGUAGE sql
AS $$
    SELECT COALESCE(SUM(quantity * unit_price - line_discount), 0)::NUMERIC(14,2)
           + COALESCE((SELECT shipping_fee FROM sales.orders WHERE order_id = p_order_id), 0)
           - COALESCE((SELECT discount_amount FROM sales.orders WHERE order_id = p_order_id), 0)
    FROM sales.order_items
    WHERE order_id = p_order_id;
$$;

CREATE OR REPLACE FUNCTION analytics.customer_ltv(p_customer_id UUID)
RETURNS NUMERIC(14,2)
LANGUAGE sql
AS $$
    SELECT COALESCE(SUM(sales.calculate_order_total(o.order_id)), 0)::NUMERIC(14,2)
    FROM sales.orders o
    WHERE o.customer_id = p_customer_id
      AND o.order_status NOT IN ('cancelled');
$$;

CREATE OR REPLACE FUNCTION analytics.top_products_by_period(p_start_date DATE, p_end_date DATE)
RETURNS TABLE (
    product_id BIGINT,
    product_name TEXT,
    units_sold BIGINT,
    revenue NUMERIC(14,2)
)
LANGUAGE sql
AS $$
    SELECT
        p.product_id,
        p.product_name,
        SUM(oi.quantity)::BIGINT AS units_sold,
        SUM(oi.quantity * oi.unit_price - oi.line_discount)::NUMERIC(14,2) AS revenue
    FROM sales.order_items oi
    JOIN sales.orders o ON o.order_id = oi.order_id
    JOIN core.products p ON p.product_id = oi.product_id
    WHERE o.order_date::DATE BETWEEN p_start_date AND p_end_date
      AND o.order_status NOT IN ('cancelled', 'refunded')
    GROUP BY p.product_id, p.product_name
    ORDER BY revenue DESC, units_sold DESC;
$$;

-- -----------------------------
-- 9. Triggers
-- -----------------------------
CREATE TRIGGER trg_customers_set_updated_at
BEFORE UPDATE ON core.customers
FOR EACH ROW
EXECUTE FUNCTION core.set_updated_at();

CREATE TRIGGER trg_orders_status_audit
AFTER UPDATE ON sales.orders
FOR EACH ROW
EXECUTE FUNCTION audit.log_order_status_change();

CREATE TRIGGER trg_customers_audit_ins_upd_del
AFTER INSERT OR UPDATE OR DELETE ON core.customers
FOR EACH ROW
EXECUTE FUNCTION audit.log_customer_change();

-- -----------------------------
-- 10. Indexes
-- -----------------------------
CREATE INDEX idx_customers_country_city ON core.customers(country_code, city_id);
CREATE INDEX idx_customers_created_at ON core.customers(created_at);
CREATE INDEX idx_customers_tags_gin ON core.customers USING GIN(tags);
CREATE INDEX idx_customers_profile_gin ON core.customers USING GIN(profile);

CREATE INDEX idx_products_category ON core.products(category_id);
CREATE INDEX idx_products_attributes_gin ON core.products USING GIN(attributes);

CREATE INDEX idx_orders_customer_id ON sales.orders(customer_id);
CREATE INDEX idx_orders_status_order_date ON sales.orders(order_status, order_date DESC);
CREATE INDEX idx_orders_extra_data_gin ON sales.orders USING GIN(extra_data);

CREATE INDEX idx_order_items_order_id ON sales.order_items(order_id);
CREATE INDEX idx_order_items_product_id ON sales.order_items(product_id);

CREATE INDEX idx_payments_order_id ON sales.payments(order_id);
CREATE INDEX idx_shipments_order_id ON sales.shipments(order_id);
CREATE INDEX idx_employee_department_salary ON hr.employees(department_id, salary DESC);

-- Partial index example
CREATE INDEX idx_orders_paid_recent
ON sales.orders(order_date DESC)
WHERE order_status IN ('paid', 'packed', 'shipped', 'delivered');

-- -----------------------------
-- 11. Seed reference data
-- -----------------------------
INSERT INTO core.countries(country_code, country_name, region) VALUES
('US', 'United States', 'North America'),
('UK', 'United Kingdom', 'Europe'),
('DE', 'Germany', 'Europe'),
('FR', 'France', 'Europe'),
('JP', 'Japan', 'Asia'),
('CA', 'Canada', 'North America'),
('BR', 'Brazil', 'South America'),
('IN', 'India', 'Asia');

INSERT INTO core.cities(country_code, city_name, timezone_name, population) VALUES
('US', 'New York', 'America/New_York', 8400000),
('US', 'Los Angeles', 'America/Los_Angeles', 3900000),
('US', 'Chicago', 'America/Chicago', 2700000),
('UK', 'London', 'Europe/London', 8900000),
('UK', 'Manchester', 'Europe/London', 550000),
('DE', 'Berlin', 'Europe/Berlin', 3700000),
('FR', 'Paris', 'Europe/Paris', 2100000),
('JP', 'Tokyo', 'Asia/Tokyo', 13900000),
('CA', 'Toronto', 'America/Toronto', 2900000),
('BR', 'Sao Paulo', 'America/Sao_Paulo', 12300000),
('IN', 'Mumbai', 'Asia/Kolkata', 12400000),
('IN', 'Bengaluru', 'Asia/Kolkata', 8400000);

INSERT INTO core.categories(category_name, parent_category_id) VALUES
('Electronics', NULL),
('Computers', 1),
('Phones', 1),
('Home', NULL),
('Kitchen', 4),
('Sports', NULL),
('Books', NULL),
('Accessories', 1);

INSERT INTO hr.departments(department_name, budget) VALUES
('Engineering', 2500000),
('Sales', 1800000),
('Finance', 900000),
('Operations', 1200000),
('HR', 500000),
('Analytics', 1100000);

INSERT INTO core.warehouses(warehouse_name, city_id, capacity, meta) VALUES
('North Hub', 1, 50000, '{"temperature_controlled": true}'),
('West Hub', 2, 45000, '{"temperature_controlled": false}'),
('Europe Hub', 4, 55000, '{"temperature_controlled": true}'),
('Asia Hub', 8, 70000, '{"temperature_controlled": true}');

-- -----------------------------
-- 12. Seed products
-- -----------------------------
INSERT INTO core.products(sku, product_name, category_id, brand, base_price, weight_kg, attributes)
SELECT
    'SKU-' || LPAD(gs::TEXT, 5, '0'),
    CASE
        WHEN gs <= 40 THEN 'Laptop Model ' || gs
        WHEN gs <= 80 THEN 'Phone Model ' || gs
        WHEN gs <= 120 THEN 'Kitchen Device ' || gs
        WHEN gs <= 160 THEN 'Sport Gear ' || gs
        ELSE 'Book Title ' || gs
    END,
    CASE
        WHEN gs <= 40 THEN 2
        WHEN gs <= 80 THEN 3
        WHEN gs <= 120 THEN 5
        WHEN gs <= 160 THEN 6
        ELSE 7
    END,
    (ARRAY['NovaTech','Skyline','Apex','GreenLeaf','UrbanWave','Zenith'])[1 + (random()*5)::INT],
    ROUND((20 + random() * 1980)::NUMERIC, 2),
    ROUND((0.1 + random() * 15)::NUMERIC, 3),
    jsonb_build_object(
        'color', (ARRAY['black','white','silver','blue','red'])[1 + (random()*4)::INT],
        'warranty_months', (ARRAY[6,12,24,36])[1 + (random()*3)::INT],
        'rating', ROUND((3 + random()*2)::NUMERIC, 1)
    )
FROM generate_series(1, 220) AS gs;

INSERT INTO core.product_prices(product_id, valid_from, valid_to, price, currency)
SELECT
    p.product_id,
    CURRENT_DATE - INTERVAL '365 days',
    NULL,
    ROUND((p.base_price * (0.9 + random() * 0.25))::NUMERIC, 2),
    'USD'
FROM core.products p;

INSERT INTO core.inventory(warehouse_id, product_id, quantity_on_hand, reorder_level)
SELECT
    w.warehouse_id,
    p.product_id,
    (20 + random() * 500)::INT,
    (5 + random() * 40)::INT
FROM core.warehouses w
CROSS JOIN core.products p;

-- -----------------------------
-- 13. Seed employees
-- -----------------------------
INSERT INTO hr.employees(manager_id, department_id, first_name, last_name, email, hire_date, status, salary, bonus_pct, skills, employee_meta)
SELECT
    NULL,
    (1 + random()*5)::INT,
    'Employee' || gs,
    'Lead' || gs,
    ('lead' || gs || '@company.demo')::core.email_address,
    CURRENT_DATE - ((1000 + random() * 2000)::INT),
    'active',
    ROUND((90000 + random() * 90000)::NUMERIC, 2),
    ROUND((5 + random() * 20)::NUMERIC, 2),
    ARRAY['management','planning','communication'],
    jsonb_build_object('level', 'lead')
FROM generate_series(1, 12) AS gs;

INSERT INTO hr.employees(manager_id, department_id, first_name, last_name, email, hire_date, status, salary, bonus_pct, skills, employee_meta)
SELECT
    (1 + random() * 11)::INT,
    (1 + random()*5)::INT,
    'Emp' || gs,
    'User' || gs,
    ('employee' || gs || '@company.demo')::core.email_address,
    CURRENT_DATE - ((30 + random() * 2500)::INT),
    (ARRAY['probation','active','vacation'])[1 + (random()*2)::INT]::hr.employment_status,
    ROUND((35000 + random() * 115000)::NUMERIC, 2),
    ROUND((0 + random() * 15)::NUMERIC, 2),
    ARRAY[
        (ARRAY['sql','python','excel','salesforce','logistics','negotiation','tableau'])[1 + (random()*6)::INT],
        (ARRAY['sql','python','excel','salesforce','logistics','negotiation','tableau'])[1 + (random()*6)::INT]
    ],
    jsonb_build_object('level', (ARRAY['junior','middle','senior'])[1 + (random()*2)::INT])
FROM generate_series(13, 180) AS gs;

INSERT INTO hr.employee_salaries(employee_id, effective_from, salary, reason)
SELECT
    e.employee_id,
    e.hire_date,
    ROUND((e.salary * (0.8 + random() * 0.1))::NUMERIC, 2),
    'Initial offer'
FROM hr.employees e
UNION ALL
SELECT
    e.employee_id,
    GREATEST(e.hire_date + INTERVAL '180 days', CURRENT_DATE - INTERVAL '400 days')::DATE,
    e.salary,
    'Annual review'
FROM hr.employees e;

-- -----------------------------
-- 14. Seed customers
-- -----------------------------
INSERT INTO core.customers(first_name, last_name, email, phone, birth_date, country_code, city_id, loyalty_points, tags, profile, created_at)
SELECT
    'Name' || gs,
    'Surname' || gs,
    ('customer' || gs || '@mail.demo')::core.email_address,
    '+100000' || LPAD(gs::TEXT, 6, '0'),
    DATE '1975-01-01' + ((random() * 15000)::INT),
    c.country_code,
    ci.city_id,
    (random() * 8000)::INT,
    ARRAY[
        (ARRAY['vip','new','newsletter','b2b','family','discount-lover'])[1 + (random()*5)::INT],
        (ARRAY['tech','sports','home','books'])[1 + (random()*3)::INT]
    ],
    jsonb_build_object(
        'preferred_language', (ARRAY['en','de','fr','pt','ja','hi'])[1 + (random()*5)::INT],
        'marketing_opt_in', (random() > 0.2),
        'risk_score', ROUND((random()*100)::NUMERIC, 2)
    ),
    NOW() - ((random() * 900)::INT || ' days')::INTERVAL
FROM generate_series(1, 3000) AS gs
CROSS JOIN LATERAL (
    SELECT country_code FROM core.countries ORDER BY random() LIMIT 1
) c
CROSS JOIN LATERAL (
    SELECT city_id FROM core.cities WHERE country_code = c.country_code ORDER BY random() LIMIT 1
) ci;

INSERT INTO core.addresses(customer_id, address_type, line1, postal_code, city_id, is_default)
SELECT
    cu.customer_id,
    'shipping',
    'Street ' || (1 + random()*999)::INT || ', Building ' || (1 + random()*40)::INT,
    LPAD((10000 + random()*89999)::INT::TEXT, 5, '0'),
    cu.city_id,
    TRUE
FROM core.customers cu;

INSERT INTO core.addresses(customer_id, address_type, line1, postal_code, city_id, is_default)
SELECT
    cu.customer_id,
    'billing',
    'Office ' || (1 + random()*500)::INT,
    LPAD((10000 + random()*89999)::INT::TEXT, 5, '0'),
    cu.city_id,
    FALSE
FROM core.customers cu
WHERE random() > 0.4;

-- -----------------------------
-- 15. Seed orders, items, payments, shipments, returns
-- -----------------------------
INSERT INTO sales.orders(customer_id, shipping_address_id, order_status, payment_method, order_date, required_date, shipped_date,
                         discount_amount, shipping_fee, notes, source_channel, extra_data)
SELECT
    cu.customer_id,
    ad.address_id,
    (ARRAY['new','paid','packed','shipped','delivered','cancelled','refunded'])[1 + (random()*6)::INT]::core.order_status,
    (ARRAY['card','cash','bank_transfer','paypal','apple_pay'])[1 + (random()*4)::INT]::core.payment_method,
    NOW() - ((random() * 720)::INT || ' days')::INTERVAL,
    CURRENT_DATE + ((random() * 10)::INT),
    CASE WHEN random() > 0.35 THEN NOW() - ((random() * 700)::INT || ' days')::INTERVAL ELSE NULL END,
    ROUND((random() * 50)::NUMERIC, 2),
    ROUND((5 + random() * 35)::NUMERIC, 2),
    CASE WHEN random() > 0.8 THEN 'Priority order' ELSE NULL END,
    (ARRAY['web','mobile','marketplace','phone'])[1 + (random()*3)::INT],
    jsonb_build_object('coupon', CASE WHEN random() > 0.7 THEN 'SALE10' ELSE NULL END,
                       'gift_wrap', (random() > 0.85))
FROM generate_series(1, 12000) gs
CROSS JOIN LATERAL (
    SELECT customer_id, city_id FROM core.customers ORDER BY random() LIMIT 1
) cu
CROSS JOIN LATERAL (
    SELECT address_id FROM core.addresses WHERE customer_id = cu.customer_id AND address_type = 'shipping' ORDER BY random() LIMIT 1
) ad;

INSERT INTO sales.order_items(order_id, product_id, warehouse_id, quantity, unit_price, line_discount)
SELECT
    o.order_id,
    p.product_id,
    w.warehouse_id,
    (1 + random() * 4)::INT,
    ROUND((p.base_price * (0.85 + random()*0.35))::NUMERIC, 2),
    ROUND((random() * 25)::NUMERIC, 2)
FROM sales.orders o
CROSS JOIN LATERAL (
    SELECT product_id, base_price FROM core.products ORDER BY random() LIMIT (1 + (random()*3)::INT)
) p
CROSS JOIN LATERAL (
    SELECT warehouse_id FROM core.warehouses ORDER BY random() LIMIT 1
) w
ON CONFLICT DO NOTHING;

INSERT INTO sales.payments(order_id, payment_date, amount, method, is_successful, response_payload)
SELECT
    o.order_id,
    o.order_date + ((random() * 48)::INT || ' hours')::INTERVAL,
    GREATEST(0, sales.calculate_order_total(o.order_id)),
    COALESCE(o.payment_method, 'card'::core.payment_method),
    (o.order_status <> 'cancelled'),
    jsonb_build_object('gateway', (ARRAY['stripe','adyen','paypal'])[1 + (random()*2)::INT],
                       'approved', (o.order_status <> 'cancelled'))
FROM sales.orders o
WHERE o.order_status IN ('paid','packed','shipped','delivered','refunded')
  AND random() > 0.08;

INSERT INTO sales.shipments(order_id, warehouse_id, shipped_at, delivered_at, carrier, tracking_number, shipping_cost, status)
SELECT
    o.order_id,
    COALESCE((SELECT warehouse_id FROM sales.order_items oi WHERE oi.order_id = o.order_id LIMIT 1), 1),
    o.order_date + ((1 + random()*7)::INT || ' days')::INTERVAL,
    CASE WHEN o.order_status = 'delivered'
         THEN o.order_date + ((3 + random()*12)::INT || ' days')::INTERVAL
         ELSE NULL END,
    (ARRAY['DHL','UPS','FedEx','Royal Mail'])[1 + (random()*3)::INT],
    'TRK' || LPAD(o.order_id::TEXT, 10, '0'),
    ROUND((5 + random()*20)::NUMERIC, 2),
    CASE
        WHEN o.order_status = 'delivered' THEN 'delivered'
        WHEN o.order_status IN ('shipped','packed') THEN 'in_transit'
        ELSE 'created'
    END
FROM sales.orders o
WHERE o.order_status IN ('packed','shipped','delivered');

INSERT INTO sales.returns(order_item_id, return_date, quantity, reason, refund_amount)
SELECT
    oi.order_item_id,
    o.order_date + ((15 + random()*40)::INT || ' days')::INTERVAL,
    1,
    (ARRAY['damaged','wrong item','late delivery','changed mind'])[1 + (random()*3)::INT],
    ROUND((LEAST(oi.unit_price, oi.unit_price - oi.line_discount))::NUMERIC, 2)
FROM sales.order_items oi
JOIN sales.orders o ON o.order_id = oi.order_id
WHERE o.order_status IN ('delivered','refunded')
  AND random() > 0.96;

-- -----------------------------
-- 16. Views and materialized view
-- -----------------------------
CREATE OR REPLACE VIEW analytics.v_order_totals AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_date,
    sales.calculate_order_total(o.order_id) AS order_total,
    COUNT(oi.order_item_id) AS line_count,
    SUM(oi.quantity) AS total_units
FROM sales.orders o
LEFT JOIN sales.order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.order_status, o.order_date;

CREATE OR REPLACE VIEW analytics.v_customer_summary AS
SELECT
    c.customer_id,
    c.customer_code,
    c.first_name,
    c.last_name,
    c.email,
    c.country_code,
    COUNT(DISTINCT o.order_id) AS order_count,
    COALESCE(SUM(vot.order_total), 0)::NUMERIC(14,2) AS revenue,
    MAX(o.order_date) AS last_order_at,
    analytics.customer_ltv(c.customer_id) AS lifetime_value
FROM core.customers c
LEFT JOIN sales.orders o ON o.customer_id = c.customer_id
LEFT JOIN analytics.v_order_totals vot ON vot.order_id = o.order_id
GROUP BY c.customer_id, c.customer_code, c.first_name, c.last_name, c.email, c.country_code;

CREATE MATERIALIZED VIEW analytics.mv_daily_sales AS
SELECT
    o.order_date::DATE AS sales_day,
    COUNT(DISTINCT o.order_id) AS orders_cnt,
    COUNT(DISTINCT o.customer_id) AS customers_cnt,
    SUM(oi.quantity) AS units_sold,
    SUM(oi.quantity * oi.unit_price - oi.line_discount) AS gross_revenue,
    AVG(oi.unit_price) AS avg_item_price
FROM sales.orders o
JOIN sales.order_items oi ON oi.order_id = o.order_id
WHERE o.order_status NOT IN ('cancelled')
GROUP BY o.order_date::DATE;

CREATE UNIQUE INDEX idx_mv_daily_sales_day ON analytics.mv_daily_sales(sales_day);

-- -----------------------------
-- 17. Example updates to fire triggers
-- -----------------------------
UPDATE core.customers
SET loyalty_points = loyalty_points + 10
WHERE customer_id IN (
    SELECT customer_id FROM core.customers ORDER BY created_at DESC LIMIT 5
);

UPDATE sales.orders
SET order_status = 'paid'
WHERE order_id IN (
    SELECT order_id FROM sales.orders WHERE order_status = 'new' ORDER BY order_date DESC LIMIT 10
);

COMMIT;

-- =========================================================
-- 18. THEORY DEMO QUERIES
-- Run these manually after loading the script.
-- =========================================================

-- -----------------------------
-- FROM
-- -----------------------------
-- SELECT * FROM core.customers;
-- SELECT * FROM (SELECT * FROM core.customers WHERE first_name LIKE 'Name1%') t;

-- -----------------------------
-- JOIN (INNER / LEFT / RIGHT / FULL / CROSS / SELF / USING)
-- -----------------------------
-- INNER JOIN
-- SELECT o.order_id, c.first_name, c.last_name, o.order_status
-- FROM sales.orders o
-- JOIN core.customers c ON o.customer_id = c.customer_id
-- LIMIT 20;

-- LEFT JOIN
-- SELECT c.customer_id, c.email, o.order_id
-- FROM core.customers c
-- LEFT JOIN sales.orders o ON o.customer_id = c.customer_id
-- WHERE o.order_id IS NULL
-- LIMIT 20;

-- FULL JOIN
-- SELECT c.customer_id, o.order_id
-- FROM core.customers c
-- FULL JOIN sales.orders o ON o.customer_id = c.customer_id
-- LIMIT 20;

-- CROSS JOIN
-- SELECT w.warehouse_name, d.department_name
-- FROM core.warehouses w
-- CROSS JOIN hr.departments d
-- LIMIT 12;

-- SELF JOIN
-- SELECT e.employee_id, e.first_name, e.last_name,
--        m.employee_id AS manager_id, m.first_name AS manager_first_name
-- FROM hr.employees e
-- LEFT JOIN hr.employees m ON e.manager_id = m.employee_id
-- LIMIT 25;

-- -----------------------------
-- WHERE
-- -----------------------------
-- SELECT *
-- FROM sales.orders o
-- JOIN core.customers c ON o.customer_id = c.customer_id
-- WHERE c.country_code = 'UK'
--   AND o.order_status IN ('paid','shipped','delivered');

-- Same filter moved closer to JOIN predicate:
-- SELECT *
-- FROM sales.orders o
-- JOIN core.customers c
--   ON o.customer_id = c.customer_id
--  AND c.country_code = 'UK';

-- -----------------------------
-- GROUP BY / HAVING
-- -----------------------------
-- SELECT c.country_code, COUNT(*) AS customers_cnt
-- FROM core.customers c
-- GROUP BY c.country_code
-- ORDER BY customers_cnt DESC;

-- SELECT c.country_code, ci.city_name, COUNT(*) AS customers_cnt
-- FROM core.customers c
-- JOIN core.cities ci ON ci.city_id = c.city_id
-- GROUP BY c.country_code, ci.city_name
-- HAVING COUNT(*) > 100
-- ORDER BY customers_cnt DESC, ci.city_name;

-- HAVING without GROUP BY
-- SELECT COUNT(*) AS orders_cnt
-- FROM sales.orders
-- HAVING COUNT(*) > 1000;

-- -----------------------------
-- SELECT expressions / aliases
-- -----------------------------
-- SELECT product_name,
--        base_price,
--        base_price * 1.2 AS price_with_markup
-- FROM core.products
-- LIMIT 20;

-- -----------------------------
-- ORDER BY / LIMIT / OFFSET
-- -----------------------------
-- SELECT employee_id, first_name, salary
-- FROM hr.employees
-- ORDER BY salary DESC
-- LIMIT 10 OFFSET 5;

-- -----------------------------
-- Aggregate functions
-- -----------------------------
-- SELECT
--     MIN(base_price) AS min_price,
--     MAX(base_price) AS max_price,
--     AVG(base_price) AS avg_price,
--     SUM(base_price) AS total_price,
--     COUNT(*) AS products_cnt
-- FROM core.products;

-- -----------------------------
-- Window functions
-- -----------------------------
-- SELECT
--     employee_id,
--     department_id,
--     salary,
--     RANK() OVER (PARTITION BY department_id ORDER BY salary DESC) AS salary_rank,
--     AVG(salary) OVER (PARTITION BY department_id) AS avg_department_salary,
--     SUM(salary) OVER (PARTITION BY department_id ORDER BY salary DESC) AS running_salary_sum
-- FROM hr.employees;

-- -----------------------------
-- CTEs
-- -----------------------------
-- WITH customer_orders AS (
--     SELECT customer_id, COUNT(*) AS order_cnt
--     FROM sales.orders
--     GROUP BY customer_id
-- )
-- SELECT c.customer_id, c.email, co.order_cnt
-- FROM customer_orders co
-- JOIN core.customers c ON c.customer_id = co.customer_id
-- WHERE co.order_cnt >= 5
-- ORDER BY co.order_cnt DESC
-- LIMIT 20;

-- -----------------------------
-- Subqueries
-- -----------------------------
-- SELECT *
-- FROM core.products
-- WHERE product_id IN (
--     SELECT DISTINCT product_id
--     FROM sales.order_items
--     WHERE quantity >= 4
-- );

-- Correlated subquery
-- SELECT c.customer_id, c.email
-- FROM core.customers c
-- WHERE EXISTS (
--     SELECT 1
--     FROM sales.orders o
--     WHERE o.customer_id = c.customer_id
--       AND o.order_status = 'delivered'
-- );

-- -----------------------------
-- JSON / ARRAY examples
-- -----------------------------
-- SELECT customer_id, profile->>'preferred_language' AS preferred_language
-- FROM core.customers
-- WHERE profile->>'marketing_opt_in' = 'true'
-- LIMIT 20;

-- SELECT customer_id, tags
-- FROM core.customers
-- WHERE tags @> ARRAY['vip']::TEXT[]
-- LIMIT 20;

-- -----------------------------
-- Views / materialized views
-- -----------------------------
-- SELECT * FROM analytics.v_order_totals ORDER BY order_total DESC LIMIT 20;
-- SELECT * FROM analytics.v_customer_summary ORDER BY lifetime_value DESC LIMIT 20;
-- SELECT * FROM analytics.mv_daily_sales ORDER BY sales_day DESC LIMIT 20;
-- REFRESH MATERIALIZED VIEW analytics.mv_daily_sales;

-- -----------------------------
-- Functions
-- -----------------------------
-- SELECT sales.calculate_order_total(1);
-- SELECT analytics.customer_ltv((SELECT customer_id FROM core.customers LIMIT 1));
-- SELECT * FROM analytics.top_products_by_period(CURRENT_DATE - 90, CURRENT_DATE);

-- -----------------------------
-- Trigger / audit demonstration
-- -----------------------------
-- UPDATE sales.orders SET order_status = 'shipped' WHERE order_id = 1;
-- SELECT * FROM audit.order_status_log ORDER BY changed_at DESC LIMIT 20;

-- UPDATE core.customers
-- SET last_name = last_name || '_updated'
-- WHERE customer_id = (SELECT customer_id FROM core.customers LIMIT 1);
-- SELECT * FROM audit.customer_audit ORDER BY changed_at DESC LIMIT 20;

-- -----------------------------
-- DML examples
-- -----------------------------
-- INSERT INTO core.categories(category_name) VALUES ('Pets');
-- UPDATE core.products SET base_price = base_price * 1.05 WHERE category_id = 7;
-- DELETE FROM sales.returns WHERE return_date < CURRENT_DATE - INTERVAL '365 days';

-- -----------------------------
-- DDL examples
-- -----------------------------
-- CREATE TABLE analytics.temp_demo(id INT);
-- ALTER TABLE analytics.temp_demo ADD COLUMN note TEXT;
-- TRUNCATE TABLE analytics.temp_demo;
-- DROP TABLE analytics.temp_demo;

-- -----------------------------
-- TCL examples
-- -----------------------------
-- BEGIN;
-- UPDATE hr.employees SET salary = salary * 1.1 WHERE department_id = 1;
-- SAVEPOINT before_second_update;
-- UPDATE hr.employees SET salary = salary * 10 WHERE employee_id = 1;
-- ROLLBACK TO SAVEPOINT before_second_update;
-- COMMIT;

-- -----------------------------
-- DCL examples (run with proper permissions)
-- -----------------------------
-- CREATE ROLE demo_reader LOGIN PASSWORD 'StrongPassword123!';
-- GRANT USAGE ON SCHEMA core, sales, hr, analytics TO demo_reader;
-- GRANT SELECT ON ALL TABLES IN SCHEMA core, sales, hr, analytics TO demo_reader;
-- REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM demo_reader;

-- -----------------------------
-- EXPLAIN / optimization examples
-- -----------------------------
-- EXPLAIN ANALYZE
-- SELECT *
-- FROM sales.orders
-- WHERE order_status = 'delivered'
-- ORDER BY order_date DESC
-- LIMIT 50;

-- EXPLAIN ANALYZE
-- SELECT c.country_code, COUNT(*)
-- FROM core.customers c
-- GROUP BY c.country_code;

-- =========================================================
-- End of file
-- =========================================================
