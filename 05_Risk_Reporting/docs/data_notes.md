# Data notes: Olist tables used in the unusual orders report

Explored by hand in PostgreSQL (`raw.*` schema), 27–28 Oct 2026. Reference for building and reviewing the SQL views.

## How the tables connect

```
customers 1 ── 1 orders 1 ── 0..many order_items many ── 1 sellers
                    │
                    1
                    │
                 0..many
             order_payments
```

- `orders` is the centre. Every count in the report starts from it.
- Sellers reach orders **only through `order_items`**. An order with no items has no seller.
- **"Many" lines multiply rows.** Joining to `order_items` or `order_payments` and then using `COUNT(*)` or `SUM` counts an order more than once. Use `COUNT(DISTINCT order_id)`, or aggregate to one row per order before joining.

## orders

- **One row** = one order. **Key:** `order_id`, unique (99,441 rows = 99,441 IDs).
- **Dates:** purchases run 4 Sep 2016 – 17 Oct 2018. Thin at both ends (Sep 2016: 4 orders, Dec 2016: 1, Sep–Oct 2018: 20). Report window: 2 Jan 2017 – 26 Aug 2018.
- **Statuses:** delivered 96,478 · shipped 1,107 · canceled 625 · unavailable 609 · invoiced 314 · processing 301 · created 5 · approved 2.
- **Missing dates follow the status.** Mostly expected (an order that never shipped has no shipping date).
- **Cancelled orders by stage reached** (checked: no stage is skipped):

  | Stage before cancelling | Orders |
  |---|---|
  | Never approved | 141 |
  | Approved, never shipped | 409 |
  | Shipped, never delivered | 69 |
  | Delivered, then cancelled (possible returns) | 6 |
  | **Total** | **625** |

- **Surprises:** 23 delivered orders have a missing date (14 no approval, mostly 17–19 Feb 2017; 2 no carrier date; 8 no delivery date; one order is in two of these lists). None are canceled or unavailable → **no effect on this report**. Leave them out of only time-based metrics.

## order_items

- **One row** = one item within an order. **Key:** `order_id` + `order_item_id` (composite, unique; 112,650 rows).
- `order_item_id` = line number inside the order (1, 2, 3…). `product_id` = what was bought.
- `shipping_limit_date` = seller's deadline to hand the item to the carrier. `price` = item price without shipping. `freight_value` = shipping cost for that item.
- **No missing values.**
- **Covers 98,666 orders. 775 orders have no items:** unavailable 603, canceled 164, created 5, invoiced 2, shipped 1.
  → **767 unusual orders have no seller = the "Unattributed" row.** The 3 shipped/invoiced are odd but out of scope.
- **Values:** 1–21 items per order; 1–5 sellers per order. Price R$0.85 – 6,735. Freight R$0 – 409.68 (383 free-shipping items).
- **Multi-seller orders:** 1,278 overall, but only 1 is unusual, and it falls outside the window → by-seller totals reconcile. **Recheck at every refresh.**
- Items under R$2: not yet checked. Not relevant to this report.

## sellers

- **One row** = one seller with their location. **Key:** `seller_id`, unique (3,095).
- **No missing values.** Every seller in `order_items` exists here.
- **23 states, very lopsided:** SP has 59.7% of sellers; several states (e.g. MA, AC, PI, PA, AM) have about 1.
  → **Region rule:** states with fewer than 10 unusual orders in the window are grouped as **"Other"**, so totals still reconcile.
- **City names are messy** (e.g. 13 spellings matching "paulo"). Not used: report uses `seller_state`.

## customers

- **One row** = one customer **per order**. `customer_id` matches orders 1-to-1 (99,441). `customer_unique_id` = the real person (96,096).
- Joining `orders` → `customers` never duplicates orders, so the customer-region view is safe.
- **No missing states.** Every order has a customer.
- **All 27 states.** Less lopsided than sellers (SP 42%). Small states (RR, AM, AC, AP) → same "Other" rule.
- City names messy, not used.

## order_payments

- **One row** = one payment for an order. **Key:** `order_id` + `payment_sequential` (unique; 103,886 rows, 99,440 orders).
- **Several rows per order** (2,961 orders), e.g. a credit card plus several vouchers. → **Sum payments per order before joining.**
- `payment_installments` = how many monthly parts a card payment was split into (up to 24). The full amount is still in `payment_value`. Not used.
- **Types:** credit_card 76,795 · boleto 19,784 · voucher 5,775 · debit_card 1,529 · not_defined 3.
- **Surprises:**
  - 3 `not_defined` payments are R$0, all on cancelled orders. They count as having a payment but add R$0 to "value paid".
  - 6 zero-value vouchers (believable: fully discounted).
  - 1 delivered order has no payment row. Out of scope.

## Worked example: one cancelled order end to end

Order `714fb133a6730ab81fa1d3c1b2007291`: bought 26 Jan 2018 → approved 26 Jan → shipped 29 Jan → **cancelled in transit, never delivered** (one of the 69).
1 item from seller `95f83f51…` (MG) to a customer in SP. Price R$69.90 + freight R$26.11 = **R$96.01 = credit card payment** (reconciles).
Same order counts under **MG** by seller region and **SP** by customer region, so the report must say which one it uses.
